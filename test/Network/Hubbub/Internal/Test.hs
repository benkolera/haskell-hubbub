module Network.Hubbub.Internal.Test (internalSuite) where

import Network.Hubbub.Internal (doSubscriptionEvent)
import Network.Hubbub.SubscriptionDb
  ( Callback
  , GetTopicSubscriptions(GetTopicSubscriptions)
  , SubscriptionDb(SubscriptionDb)
  , Subscription(Subscription)
  , Topic
  , emptyDb)
import Network.Hubbub.Queue
  ( SubscriptionEvent(SubscribeEvent,UnsubscribeEvent)
  , LeaseSeconds(LeaseSeconds)
  )
import Network.Hubbub.TestHelpers
  ( assertRightEitherT
  , scottyTest
  , localTopic
  , localCallback )

import Prelude (undefined)
import Control.Monad (return)
import Data.Acid (AcidState,IsAcidic,query)
import Data.Acid.Memory (openMemoryState)
import Data.Function (($))
import Data.Maybe (Maybe(Nothing,Just))
import Data.Map (lookup,fromList)
import System.IO (IO)
import System.Random (StdGen,getStdGen)
import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit (Assertion,testCase,assertFailure)
import Web.Scotty (ScottyM,get,param,text)

internalSuite :: TestTree
internalSuite = testGroup "Internal" 
  [ testCase "subscribe" subscribeDoSubscriptionEventTest
  , testCase "unsubscribe" unsubscribeDoSubscriptionEventTest
  , testCase "subscribeError" subscribeErrorDoSubscriptionEventTest
  , testCase "unsubscribeError" unsubscribeErrorDoSubscriptionEventTest ]

subscribeDoSubscriptionEventTest :: Assertion
subscribeDoSubscriptionEventTest = acidTest goodSubscriber emptyDb test
  where
    test acid rng =
      runSubscriptionEvent acid rng testSubscribe assertSubscription
  
unsubscribeDoSubscriptionEventTest :: Assertion
unsubscribeDoSubscriptionEventTest = acidTest goodSubscriber emptyDb test
  where
    test acid rng = do
      runSubscriptionEvent acid rng testSubscribe assertSubscription
      runSubscriptionEvent acid rng testUnsubscribe assertNoSubscription      

subscribeErrorDoSubscriptionEventTest :: Assertion
subscribeErrorDoSubscriptionEventTest = acidTest badSubscriber emptyDb test
  where
    test acid rng = 
      runSubscriptionEvent acid rng testSubscribe assertNoSubscription

unsubscribeErrorDoSubscriptionEventTest :: Assertion
unsubscribeErrorDoSubscriptionEventTest = acidTest badSubscriber db test
  where
    test acid rng = 
      runSubscriptionEvent acid rng testUnsubscribe assertSubscription
    db = SubscriptionDb (fromList [(localTopic [],topicSubs)])
    topicSubs = fromList [(localCallback [],sub)] 
    sub = Subscription undefined undefined undefined undefined

runSubscriptionEvent ::
  AcidState SubscriptionDb ->
  StdGen ->
  SubscriptionEvent ->
  (Maybe Subscription -> Assertion) ->
  Assertion
runSubscriptionEvent acid rng ev assertion = do
  assertRightEitherT $ doSubscriptionEvent rng acid ev
  subscription <- findLocalSubscription acid
  assertion subscription  

assertSubscription :: Maybe Subscription -> Assertion
assertSubscription Nothing = assertFailure "No subscription"
assertSubscription (Just _ ) = return ()

assertNoSubscription :: Maybe Subscription -> Assertion
assertNoSubscription Nothing = return ()
assertNoSubscription (Just _ ) = assertFailure "sub not removed!"

findLocalSubscription :: AcidState SubscriptionDb -> IO (Maybe Subscription)
findLocalSubscription = findSubscription (localTopic []) (localCallback [])

findSubscription :: Topic -> Callback -> AcidState SubscriptionDb -> IO (Maybe Subscription)
findSubscription t cb acid = do
  res <- query acid (GetTopicSubscriptions t)
  return (lookup cb res)

testSubscribe :: SubscriptionEvent
testSubscribe =
  SubscribeEvent
  (localTopic [])
  (localCallback [])
  (LeaseSeconds 1337)
  Nothing
  Nothing

testUnsubscribe :: SubscriptionEvent
testUnsubscribe = UnsubscribeEvent (localTopic []) (localCallback [])

acidTest :: (IsAcidic s) =>
  ScottyM () ->
  s ->
  (AcidState s -> StdGen -> Assertion) ->
  Assertion
acidTest sm init assert = scottyTest sm $ do
  acid <- openMemoryState init
  rng  <- getStdGen
  assert acid rng

goodSubscriber :: ScottyM ()
goodSubscriber = get "/callback" $ do
  challenge <- param "hub.challenge"
  text challenge

badSubscriber :: ScottyM ()
badSubscriber = return ()
