module Main where

import Hubbub.Subscriptions.Test
import Test.Tasty (defaultMain,testGroup,TestTree)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "All Tests" [subscriptionsSuite]
