module Hubbub.Subscriptions.Test (subscriptionsSuite) where

import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit
import Hubbub.Subscriptions
import qualified Data.Map as Map
import Data.Time
import Data.Acid.Memory.Pure

subscriptionsSuite :: TestTree
subscriptionsSuite = testGroup "Subscriptions" [
  testCase "Empty" testEmpty
  , testCase "Subscribe" testSubscribe
  , testCase "GetMissingSub" testGetMissingSub
  , testCase "GetAllSubs" testGetAll
  ]

testEmpty :: Assertion
testEmpty = [] @=? (Map.elems $ allSubscriptions emptyDb)

testSubscribe :: Assertion
testSubscribe = do
  time <- getCurrentTime
  (expectedSubs time) @=? (fst $ runUpdate (prog time) emptyDb)
  where
    topic = Topic "topic"
    cbUrl = CallbackUrl "callback"
    expectedSubs time = Map.fromList [(cbUrl,Subscription time)]
    prog time = do
      _ <- subscribe topic cbUrl $ Subscription time
      liftQuery $ getTopicSubscriptions topic

testGetMissingSub :: Assertion
testGetMissingSub = Map.empty @=? (runQuery q emptyDb)
  where
    q = getTopicSubscriptions $ Topic "Missing"

testGetAll :: Assertion
testGetAll = do
  time <- getCurrentTime
  (fst $ res time) @=? (allSubscriptions . snd $ res time)
  where
    res time = runUpdate (prog time) emptyDb
    prog time = do
      _ <- subscribe (Topic "topic1") (CallbackUrl "cb1") $ Subscription time
      _ <- subscribe (Topic "topic1") (CallbackUrl "cb2") $ Subscription time
      _ <- subscribe (Topic "topic2") (CallbackUrl "cb3") $ Subscription time      
      liftQuery $ getAllSubscriptions
