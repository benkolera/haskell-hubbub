module Network.Hubbub.SubscriptionDb.Acid.Test (subscriptionDbAcidSuite) where

import Network.Hubbub.SubscriptionDb
  ( Subscription(Subscription)
  , From(From) )
import Network.Hubbub.SubscriptionDb.Acid
import Network.Hubbub.TestHelpers

import Prelude (($),(.),Maybe(Nothing,Just),fst,snd)
import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit ((@=?),testCase,Assertion)
import Data.DateTime (addSeconds)
import qualified Data.Map as Map
import Data.Time (getCurrentTime,UTCTime)
import Data.Acid.Memory.Pure (runUpdate,liftQuery,runQuery)
import Data.Text (Text)

subscriptionDbAcidSuite :: TestTree
subscriptionDbAcidSuite = testGroup "SubscriptionDbAcid" [
  testCase "Empty" testEmpty
  , testCase "AddSubscription" testAddSubscription
  , testCase "GetMissingSub" testGetMissingSub
  , testCase "GetAllSubs" testGetAll
  ]

testEmpty :: Assertion
testEmpty = [] @=? Map.elems ( allSubscriptions emptyDb )

testAddSubscription :: Assertion
testAddSubscription = do
  time <- getCurrentTime
  expectedSubs time @=? fst (runUpdate (prog time) emptyDb)
  where
    t = topic "topic"
    cb = callback "callback"
    expectedSubs time = Map.fromList [(cb,subscription time "foo")]
    prog time = do
      _ <- addSubscription t cb $ subscription time "foo"
      liftQuery $ getTopicSubscriptions t

testGetMissingSub :: Assertion
testGetMissingSub = Map.empty @=? runQuery q emptyDb
  where
    q = getTopicSubscriptions $ topic "Missing"

testGetAll :: Assertion
testGetAll = do
  time <- getCurrentTime
  fst (res time) @=? (allSubscriptions . snd $ res time)
  where
    res time = runUpdate (prog time) emptyDb
    prog t = do
      _ <- addSub "a" t
      _ <- addSub "b" t
      _ <- addSub "c" t
      liftQuery getAllSubscriptions
    addSub n t = addSubscription (topic n) (callback n) $ subscription t "foo"

subscription :: UTCTime -> Text -> Subscription
subscription t n = Subscription t (addSeconds 300 t) Nothing (Just . From $ n)
