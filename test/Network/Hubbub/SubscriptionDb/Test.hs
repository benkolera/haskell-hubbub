module Network.Hubbub.SubscriptionDb.Test (subscriptionDbSuite) where

import Network.Hubbub.SubscriptionDb.Acid.Test (subscriptionDbAcidSuite)
import Network.Hubbub.SubscriptionDb.SqLite.Test (subscriptionDbSqLiteSuite)

import Test.Tasty (testGroup, TestTree)

subscriptionDbSuite :: TestTree
subscriptionDbSuite = testGroup "SubscriptionDb"
  [ subscriptionDbAcidSuite
  , subscriptionDbSqLiteSuite ]
