module Main where

import Network.Hubbub.Queue.Test
import Network.Hubbub.SubscriptionDb.Test
import Network.Hubbub.Http.Test
import Network.Hubbub.Hmac.Test
import Network.Hubbub.Internal.Test
import Network.Hubbub.Test 

import Prelude (IO)
import Test.Tasty (defaultMain,testGroup,TestTree)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "All Tests" 
  [ subscriptionDbSuite
  , queueSuite
  , httpSuite
  , hmacSuite
  , internalSuite
  , hubbubSuite
  ]
