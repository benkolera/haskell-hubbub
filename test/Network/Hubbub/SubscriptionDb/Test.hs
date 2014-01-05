module Network.Hubbub.SubscriptionDb.Test (subscriptionDbSuite) where

import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit
import Network.Hubbub.SubscriptionDb
import qualified Data.Map as Map
import Data.Time
import Data.Acid.Memory.Pure
import Network.URL
import Data.Text

subscriptionDbSuite :: TestTree
subscriptionDbSuite = testGroup "SubscriptionDb" [
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

topic :: String -> Topic
topic n    = Topic $ url "publish.com" ("/topic/" ++ n)

callback :: String -> Callback
callback n = Callback $ url "subscribe.com" ("/callback/" ++ n)

url :: String -> String -> URL
url hostNm path = URL (Absolute $ Host (HTTP False) hostNm Nothing) path []

subscription :: UTCTime -> String -> Subscription
subscription t n = Subscription t Nothing Nothing (Just . From . pack $ n)
