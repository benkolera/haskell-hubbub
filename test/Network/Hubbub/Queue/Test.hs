module Network.Hubbub.Queue.Test (queueSuite) where

import Network.Hubbub.Queue
import Network.Hubbub.TestHelpers

import Prelude ((+))
import Control.Concurrent (forkIO,threadDelay)
import Control.Concurrent.MVar
  ( newEmptyMVar
  , newMVar
  , putMVar
  , takeMVar
  , modifyMVar_ )
import Control.Concurrent.STM (STM,TQueue,atomically,newTQueue,writeTQueue)
import Control.Monad (return)
import Control.Monad.IO.Class (liftIO)
import Control.Error (EitherT,left)
import Data.Function (($),(.))
import Data.Eq (Eq,(==))
import Data.List (unwords,(++))
import Data.Maybe (Maybe(Nothing,Just),maybe)
import Data.String (String)
import Data.Text (Text)
import System.Timeout (timeout)
import System.IO (IO)
import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit ((@?=),Assertion,testCase)
import Text.Show (Show,show)

--------------------------------------------------------------------------------
-- Our TestTasty.TestTree
--------------------------------------------------------------------------------

queueSuite :: TestTree
queueSuite = testGroup "Queue" 
  [ testCase "subscribe" testSubscribe
  , testCase "publish" testPublish
  , testCase "distribute" testDistribute
  , testCase "retryable" testRetryable
  ]

--------------------------------------------------------------------------------
-- These tests test whether the event gets put into the action handler or not
--------------------------------------------------------------------------------

loopTest :: (Show a,Eq a) =>
  STM (TQueue a)  ->                         -- A stm that will create the queue
  (TQueue a -> a -> STM ()) ->               -- Enqueue STM function
  ((a -> EitherT e IO ()) ->                 -- The event loop to test
   (a -> e -> Maybe RetryDelay -> IO ()) ->  
   TQueue a ->                                
   IO ()
  ) ->
  a ->                                       -- The event to expect
  Assertion
loopTest mkQueue enqueue loop e = do
  -- Create a mutable var to capture the emitted event
  mVar  <- newEmptyMVar
  -- Make the queue
  q     <- atomically mkQueue
  -- Run the loop with a handler that just sets the mutable var
  _     <- forkIO $ loop (liftIO . putMVar mVar) (\ _ _ _ -> return ()) q
  -- Run the enqueue action
  atomically $ enqueue q e
  -- Wait at most 500 ms for the event
  event <- timeout 5000000 $ takeMVar mVar
  -- And make sure it is the one that was expected.
  Just e @?= event

testSubscribe :: Assertion 
testSubscribe = 
  loopTest 
    emptySubscriptionQueue 
    subscribe 
    subscriptionLoop 
    (subscribeEvent "a")
    
testPublish :: Assertion 
testPublish = 
  loopTest 
    emptyPublicationQueue 
    publish 
    publicationLoop 
    (publicationEvent "a")

testDistribute :: Assertion 
testDistribute = 
  loopTest 
    emptyDistributionQueue 
    distribute 
    distributionLoop 
    (distributionEvent "a")    

subscribeEvent :: Text -> SubscriptionEvent
subscribeEvent n =
  Subscribe 
  (topic n)
  (callback n)
  (LeaseSeconds 1337)
  (AttemptCount 1)
  Nothing
  Nothing

publicationEvent :: Text -> PublicationEvent
publicationEvent n = PublicationEvent (topic n) (AttemptCount 1)

distributionEvent :: Text -> DistributionEvent
distributionEvent n =
  DistributionEvent
  (topic n)
  (callback n)
  Nothing
  (ResourceBody "")
  Nothing
  (AttemptCount 1)

--------------------------------------------------------------------------------
-- Testing the retry functionality
--------------------------------------------------------------------------------

-- Make a new type just for testing and implement Retryable.

data MockRetryable = MockRetryable AttemptCount deriving (Show)
instance Retryable MockRetryable where
  attempts (MockRetryable (AttemptCount c)) = c
  incrementAttempts (MockRetryable (AttemptCount c)) =
    MockRetryable . AttemptCount $ c + 1
  retryDelay ev =
    if attempts ev == 2
    then Just (RetryDelayMillis 50)
    else Nothing
  

testRetryable :: Assertion
testRetryable = do
  -- Create a new mutable var for the string log of what we expect to happen
  mVar  <- newMVar ([]::[String])
  q     <- atomically newTQueue

  -- Run the loop with handlers that append to the log
  _     <- forkIO $ queueLoop (handleEvent mVar) (handleError mVar) q

  -- Push an event onto the queue
  atomically $ writeTQueue q . MockRetryable . AttemptCount $ 1
  -- Wait some time for the logs to accumulate. 100ms is plenty enough.
  threadDelay 100000
  logs <- timeout 100000 $ takeMVar mVar
  -- And make sure we got the logs that we'd expect
  logs @?= Just expectedLogs
  where
    -- This always fails after it writes the event to the log
    handleEvent mVar ev = do
      liftIO . modifyMVar_ mVar $ return . (("Event: " ++ show ev):)
      left ("Foobarred"::String)

    -- This just appends to the log
    handleError mVar ev er rd =
      modifyMVar_ mVar $ return . (retryToMsg ev er rd :)
    retryToMsg _ er =
      maybe
      (er ++ " -> Event Dropped")
      (\ (RetryDelayMillis ms) ->
        unwords [er,"-> event requeued in",show ms,"millis"] )

    expectedLogs = [
      "Foobarred -> Event Dropped"
      , "Event: MockRetryable (AttemptCount 2)"
      ,"Foobarred -> event requeued in 50 millis"
      ,"Event: MockRetryable (AttemptCount 1)" ]

--------------------------------------------------------------------------------
