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

queueSuite :: TestTree
queueSuite = testGroup "Queue" 
  [ testCase "subscribe" testSubscribe
  , testCase "publish" testPublish
  , testCase "distribute" testDistribute
  , testCase "retryable" testRetryable
  ]

loopTest :: (Show a,Eq a) =>
  STM (TQueue a)  -> 
  (TQueue a -> a -> STM ()) ->
  ((a -> EitherT e IO ()) ->
   (a -> e -> Maybe RetryDelay -> IO ()) ->
   TQueue a ->
   IO ()
  ) ->
  a ->
  Assertion
loopTest mkQueue enqueue loop e = do  
  mVar  <- newEmptyMVar
  q     <- atomically mkQueue 
  _     <- forkIO $ loop (liftIO . putMVar mVar) (\ _ _ _ -> return ()) q
  atomically $ enqueue q e
  event <- timeout 5000000 $ takeMVar mVar
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
  mVar  <- newMVar ([]::[String])
  q     <- atomically newTQueue
  _     <- forkIO $ queueLoop (handleEvent mVar) (handleError mVar) q
  atomically $ writeTQueue q . MockRetryable . AttemptCount $ 1
  threadDelay 100000
  logs <- timeout 100000 $ takeMVar mVar
  logs @?= Just expectedLogs
  where
    handleEvent mVar ev = do
      liftIO . modifyMVar_ mVar $ return . (("Event: " ++ show ev):)
      left ("Foobarred"::String)
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
    
