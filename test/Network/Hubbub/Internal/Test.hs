module Network.Hubbub.Internal.Test (internalSuite) where

import Network.Hubbub.Internal
  ( doDistributionEvent
  , doSubscriptionEvent
  , doPublicationEvent )

import Network.Hubbub.SubscriptionDb
  ( Callback
  , From(From)
  , Secret(Secret)
  , Subscription(Subscription)
  , Topic
  )

import Network.Hubbub.SubscriptionDb.Acid
  ( GetTopicSubscriptions(GetTopicSubscriptions)
  , SubscriptionDb(SubscriptionDb)
  , acidDbApi
  , emptyDb    
  )
import Network.Hubbub.Queue
  ( AttemptCount(AttemptCount)
  , ContentType(ContentType)
  , DistributionEvent(DistributionEvent)
  , ResourceBody(ResourceBody)
  , SubscriptionEvent(Subscribe,Unsubscribe)
  , PublicationEvent(PublicationEvent)
  , LeaseSeconds(LeaseSeconds)
  )
import Network.Hubbub.TestHelpers
  ( assertRightEitherT
  , callback
  , scottyTest
  , localHub
  , localTopic
  , localCallback
  , topic )

import Prelude (undefined)
import Control.Monad (return,mapM,unless)
import Data.Acid (AcidState,IsAcidic,query)
import Data.Acid.Memory (openMemoryState)
import Data.DateTime (addMinutes)
import Data.Eq ((==))
import Data.Function (($),(.))
import Data.Maybe (Maybe(Nothing,Just))
import Data.Map (lookup,fromList)
import Data.Time (getCurrentTime)
import Network.HTTP.Types.Status (status500)
import System.IO (IO)
import System.Random (StdGen,getStdGen)
import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit (Assertion,testCase,assertFailure,(@?=))
import Web.Scotty (ScottyM,body,get,param,post,reqHeader,setHeader,status,text)

internalSuite :: TestTree
internalSuite = testGroup "Internal"
  [ doSubscriptionEventSuite
  , doPublicationEventSuite
  , doDistributionEventSuite ]

--------------------------------------------------------------------------------
-- DoSubscriptionEvent
--------------------------------------------------------------------------------

doSubscriptionEventSuite :: TestTree
doSubscriptionEventSuite = testGroup "DoSubscriptionEvent" 
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
  assertRightEitherT $ doSubscriptionEvent rng (acidDbApi acid) ev
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
  Subscribe
  (localTopic [])
  (localCallback [])
  (LeaseSeconds 1337)
  (AttemptCount 1)
  Nothing
  Nothing

testUnsubscribe :: SubscriptionEvent
testUnsubscribe = Unsubscribe (localTopic []) (localCallback []) (AttemptCount 1)

--------------------------------------------------------------------------------
-- DoPublicationEvent
--------------------------------------------------------------------------------

doPublicationEventSuite :: TestTree
doPublicationEventSuite = testGroup "DoPublicationEvent"
  [testCase "basicEvent" doPublicationEventTest]

doPublicationEventTest :: Assertion
doPublicationEventTest = do
  db <- testDb
  acidTest goodPublisher db test
  where
    test acid _ = do
      distEvents <- assertRightEitherT $ doPublicationEvent (acidDbApi acid) ev
      distEvents @?= [
        dEv (callback "callbackB") Nothing
        , dEv (callback "callbackC") (Just . Secret $ "pw")
        ]
    ev = PublicationEvent (topic "topicB") (AttemptCount 1)
    dEv cb sec =
      DistributionEvent
      (topic "topicB")
      cb
      (Just . ContentType $ "application/csv")
      (ResourceBody "foo,bar")
      sec
      (AttemptCount 1)

      

--------------------------------------------------------------------------------
-- DoDistributionEvent
--------------------------------------------------------------------------------

doDistributionEventSuite :: TestTree
doDistributionEventSuite = testGroup "DoDistributionEvent"
  [testCase "basicEvent" doDistributionEventTest]

doDistributionEventTest :: Assertion
doDistributionEventTest = scottyTest subscribers $ do
  _ <- assertRightEitherT $ mapM (doDistributionEvent localHub) dEvs
  return ()
  where
    subscribers = do
      post "/callback/callbackB" $ callbackHandler Nothing
      post "/callback/callbackC" $
        callbackHandler $ Just "674cc7f271f41ec15c5f0418a0f7675525ed4304"

    callbackHandler expectedSig = do
      ct <- reqHeader "content-type"
      bd <- body 
      sg <- reqHeader "X-Hub-Signature"
      unless  (ct == Just "application/csv") $ status status500
      unless  (bd == "foo,bar")              $ status status500
      unless  (sg == expectedSig)            $ status status500
      
    dEvs = [
      dEv (callback "callbackB") Nothing
      , dEv (callback "callbackC") (Just . Secret $ "pw")
      ]
    dEv cb sec =
      DistributionEvent
      (topic "topicB")
      cb
      (Just . ContentType $ "application/csv")
      (ResourceBody "foo,bar")
      sec
      (AttemptCount 1)


testDb :: IO SubscriptionDb
testDb = do
  tm <- getCurrentTime
  let exp = addMinutes 30 tm
  return . SubscriptionDb $ fromList
    [ (topic "topicA",
       fromList [
         (callback "callbackA",
          Subscription tm exp Nothing (Just . From $ "userA"))
         ])
    , (topic "topicB",
       fromList [
         (callback "callbackB",
          Subscription tm exp Nothing (Just . From $ "userB"))
         , (callback "callbackC",
            Subscription tm exp (Just . Secret $ "pw") (Just . From $ "userC"))
         ])]

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

goodPublisher :: ScottyM ()
goodPublisher = get "/topic/topicB" $ do
  text "foo,bar"
  setHeader "Content-Type" "application/csv"

badSubscriber :: ScottyM ()
badSubscriber = return ()
