module Main where

import Network.Hubbub.Queue.Test
import Network.Hubbub.SubscriptionDb.Test
import Test.Tasty (defaultMain,testGroup,TestTree)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "All Tests" [
  subscriptionDbSuite
  , queueSuite
  ]
