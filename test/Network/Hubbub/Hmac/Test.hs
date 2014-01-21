module Network.Hubbub.Hmac.Test (hmacSuite) where

import Network.Hubbub.Hmac (hmacBody)
import Network.Hubbub.SubscriptionDb (Secret(Secret))

import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit (Assertion,testCase,(@=?))

hmacSuite :: TestTree
hmacSuite = testGroup "Hmac" 
  [testCase "hmac" hmacBodyTest]

hmacBodyTest :: Assertion
hmacBodyTest = expected @=? result
  where
    result   = hmacBody (Secret "supersecretsquirrel") "foobar"
    expected = "1ec8409d5244edbabb92624575e9b1b2f1485dbb"
