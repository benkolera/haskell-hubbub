module Network.Hubbub.Queue.Test (queueSuite) where

import Network.Hubbub.Queue
import Network.Hubbub.TestHelpers

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar,putMVar,takeMVar)
import Control.Concurrent.STM (STM,TQueue,atomically)
import Data.Function (($))
import Data.Eq (Eq)
import Data.Maybe (Maybe(Nothing,Just))
import Data.Text (Text)
import System.Timeout (timeout)
import System.IO (IO)
import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit ((@?=),Assertion,testCase)
import Text.Show (Show)

queueSuite :: TestTree
queueSuite = testGroup "Queue" 
  [ testCase "subscribe" testSubscribe
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

subscribeEvent :: Text -> SubscriptionEvent
subscribeEvent n =
  SubscribeEvent (topic n) (callback n) (LeaseSeconds 1337) Nothing Nothing

publicationEvent :: Text -> PublicationEvent
publicationEvent n = PublicationEvent (topic n)
