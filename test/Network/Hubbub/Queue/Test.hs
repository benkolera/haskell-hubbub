module Network.Hubbub.Queue.Test (queueSuite) where

import Network.Hubbub.Queue
import Network.Hubbub.TestHelpers

import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit
import Control.Concurrent.STM
import Data.Text (Text)
import Control.Concurrent.MVar (newEmptyMVar,putMVar,takeMVar)
import Control.Concurrent (forkIO)

queueSuite :: TestTree
queueSuite = testGroup "Queue" [
  testCase "subscribe" testSubscribe
  , testCase "publish" testPublish
  ]

loopTest :: (Show a,Eq a) =>
  STM (TQueue a)  -> 
  (TQueue a -> a -> STM ()) ->
  ((a -> IO ()) -> TQueue a -> IO ()) ->
  a ->
  Assertion
loopTest mkQueue enqueue loop e = do  
  mVar  <- newEmptyMVar
  q     <- atomically mkQueue 
  _     <- forkIO $ loop (putMVar mVar) q
  atomically $ enqueue q e
  event <- takeMVar mVar
  e @=? event

testSubscribe :: Assertion 
testSubscribe = 
  loopTest 
    emptySubscriptionQueue 
    subscribe 
    subscriptionLoop 
    (subscriptionEvent "a" SubscribeMode)
    
testPublish :: Assertion 
testPublish = 
  loopTest 
    emptyPublicationQueue 
    publish 
    publicationLoop 
    (publicationEvent "a")

subscriptionEvent :: Text -> Mode -> SubscriptionEvent
subscriptionEvent n m = 
  SubscriptionEvent (topic n) (callback n) m Nothing Nothing Nothing

publicationEvent :: Text -> PublicationEvent
publicationEvent n = PublicationEvent (topic n)
