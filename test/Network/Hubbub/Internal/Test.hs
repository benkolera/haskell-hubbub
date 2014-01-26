module Network.Hubbub.Internal.Test (internalSuite) where

import Network.Hubbub.Internal
  ( doDistributionEvent
  , doSubscriptionEvent
  , doPublicationEvent )

import Network.Hubbub.SubscriptionDb
  ( Callback
  , Secret(Secret)
  , Subscription(Subscription)
  , SubscriptionDbApi 
  , Topic
  , addSubscription
  , getTopicSubscriptions
  )

import Network.Hubbub.SubscriptionDb.SqLite ( sqLiteDbApi )
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
  , subscription
  , topic )

import Prelude (undefined)
import Control.Applicative ((<$>))
import Control.Monad (return,mapM,unless)
import Data.Eq ((==))
import Data.Function (($),(.))
import Data.List (find)
import Data.Maybe (Maybe(Nothing,Just))
import Data.Time (getCurrentTime)
import Data.Tuple (fst,snd)
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
subscribeDoSubscriptionEventTest = internalTest goodSubscriber test
  where
    test api rng =
      runSubscriptionEvent api rng testSubscribe assertSubscription
  
unsubscribeDoSubscriptionEventTest :: Assertion
unsubscribeDoSubscriptionEventTest = internalTest goodSubscriber test
  where
    test api rng = do
      runSubscriptionEvent api rng testSubscribe assertSubscription
      runSubscriptionEvent api rng testUnsubscribe assertNoSubscription      

subscribeErrorDoSubscriptionEventTest :: Assertion
subscribeErrorDoSubscriptionEventTest = internalTest badSubscriber test
  where
    test api rng = 
      runSubscriptionEvent api rng testSubscribe assertNoSubscription

unsubscribeErrorDoSubscriptionEventTest :: Assertion
unsubscribeErrorDoSubscriptionEventTest = internalTest badSubscriber test
  where
    test api rng = do
      tm <- getCurrentTime
      assertRightEitherT $ insertSub api tm
      runSubscriptionEvent api rng testUnsubscribe assertSubscription
    insertSub a t =
      addSubscription a (localTopic []) (localCallback []) (subscription t "")

runSubscriptionEvent ::
  SubscriptionDbApi -> 
  StdGen ->
  SubscriptionEvent ->
  (Maybe Subscription -> Assertion) ->
  Assertion
runSubscriptionEvent api rng ev assertion = do
  assertRightEitherT $ doSubscriptionEvent rng api ev
  sub <- findLocalSubscription api
  assertion sub  

assertSubscription :: Maybe Subscription -> Assertion
assertSubscription Nothing = assertFailure "No subscription"
assertSubscription (Just _ ) = return ()

assertNoSubscription :: Maybe Subscription -> Assertion
assertNoSubscription Nothing = return ()
assertNoSubscription (Just _ ) = assertFailure "sub not removed!"

findLocalSubscription :: SubscriptionDbApi -> IO (Maybe Subscription)
findLocalSubscription = findSubscription (localTopic []) (localCallback [])

findSubscription ::
  Topic ->
  Callback ->
  SubscriptionDbApi ->
  IO (Maybe Subscription)
findSubscription t cb api = do
  res <- assertRightEitherT $ getTopicSubscriptions api t
  return $ snd <$> find ((== cb) . fst) res

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
doPublicationEventTest = internalTest goodPublisher test
  where
    test api _ = do
      tm <- getCurrentTime
      _ <- assertRightEitherT $ insertSubs api tm
      distEvents <- assertRightEitherT $ doPublicationEvent api ev
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
    insertSubs a t = mapM (insertSub a t)
      [ ("topicA","callbackA",Nothing)
      , ("topicB","callbackB",Nothing)
      , ("topicB","callbackC",Just $ Secret "pw")        
      ]  
    insertSub api tm (tn,cbn,sec) =
      addSubscription
      api
      (topic tn)
      (callback cbn)
      (Subscription tm tm sec Nothing)

      

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


-- testDb :: IO SubscriptionDb
-- testDb = do
--   tm <- getCurrentTime
--   let exp = addMinutes 30 tm
--   return . SubscriptionDb $ fromList
--     [ (topic "topicA",
--        fromList [
--          (callback "callbackA",
--           Subscription tm exp Nothing (Just . From $ "userA"))
--          ])
--     , (topic "topicB",
--        fromList [
--          (callback "callbackB",
--           Subscription tm exp Nothing (Just . From $ "userB"))
--          , (callback "callbackC",
--             Subscription tm exp (Just . Secret $ "pw") (Just . From $ "userC"))
--          ])]

internalTest ::
  ScottyM () ->
  (SubscriptionDbApi -> StdGen -> Assertion) ->
  Assertion
internalTest sm assert = scottyTest sm $ do
  dbApi <- sqLiteDbApi Nothing
  rng   <- getStdGen
  assert dbApi rng

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
