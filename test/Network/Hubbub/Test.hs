module Network.Hubbub.Test (hubbubSuite) where

import Network.Hubbub
  ( Callback(Callback)
  , HttpResource(HttpResource)
  , HubbubConfig(HubbubConfig)
  , HubbubAcidConfig(HubbubAcidConfig)
  , LeaseSeconds(LeaseSeconds)
  , Secret(Secret)
  , ServerUrl(ServerUrl)
  , Topic(Topic)
  , initializeHubbubAcid
  , shutdownHubbub
  , subscribe
  , unsubscribe
  , publish )

import Network.Hubbub.TestHelpers (localHub,resource,scottyTestWithShutdown)

import Control.Applicative ((<$>))
import Control.Concurrent (threadDelay)
import Control.Concurrent.STM
  ( TQueue
  , atomically  
  , newTQueue
  , tryReadTQueue
  , writeTQueue)
import Control.Monad (return)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString.Lazy (ByteString)
import Data.Maybe (Maybe(Just,Nothing),maybe)
import Data.Function (($),(.))
import Data.List (replicate)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree,testGroup)
import Test.Tasty.HUnit (assertFailure,testCase,Assertion,(@?=))
import Web.Scotty (ScottyM,get,body,html,param,post,reqHeader,text)

hubbubSuite :: TestTree
hubbubSuite = testGroup "Hubbub"
  [testCase "integration" hubbubUberTest]


hubbubUberTest :: Assertion
hubbubUberTest = withSystemTempDirectory "HubbubUberTest" test
  where 
    test path = do
      subAQ <- atomically newTQueue
      subBQ <- atomically newTQueue
      env <- initializeHubbubAcid config (acidConfig path)
      scottyTestWithShutdown (server subAQ subBQ) (shutdownHubbub env) $ do
        sub env "a" "topic1" Nothing 
        sub env "b" "topic1" (Just (Secret "secret"))
        sub env "a" "topic2" Nothing
        -- Lets wait for the subscriptions to get stored.
        threadDelay 100000
        publish env $ topic "topic1"
        publish env $ topic "topic2"
        unsub env "a" "topic1"
        -- Lets wait on that unsubscription.
        threadDelay 100000
        publish env $ topic "topic1"
        threadDelay 2000000
        allADist <- allDist subAQ
        allBDist <- allDist subBQ
        allADist @?= [
          ("topic1",Nothing,"<html><body><p>Hello world</p></body></html>")
          ,("topic2",Nothing,"Haskell is awesome!")]
        allBDist @?= replicate 2
          ("topic1"
           , Just "999c6611d4698a3bcef56bb9a2bac1b58142fac6"
           ,"<html><body><p>Hello world</p></body></html>")

    server :: TQueue (T.Text,Maybe TL.Text,ByteString) -> TQueue (T.Text,Maybe TL.Text,ByteString) -> ScottyM ()
    server subAQ subBQ = do
      get "/publisher/topic1" $
        html "<html><body><p>Hello world</p></body></html>"
      get "/publisher/topic2" $
        text "Haskell is awesome!"
      get "/subscriber/:subscriber/:callback" verifySubscription
      post "/subscriber/a/:callback" $ recordDistribution subAQ
      post "/subscriber/b/:callback" $ recordDistribution subBQ      

    verifySubscription = do
      chal <- param "hub.challenge"
      text chal

    recordDistribution q = do
      cb <- param "callback"
      sg <- reqHeader "X-Hub-Signature"      
      b  <- body
      liftIO $ atomically $ writeTQueue q (cb,sg,b)

    sub env cb t sec =
      subscribe env (topic t) (callback cb t) (LeaseSeconds 500) sec Nothing
    unsub env cb t = unsubscribe env (topic t) (callback cb t)

    callback cbName tName =
      Callback $ resource (T.concat ["/subscriber/",cbName,"/",tName]) []
    topic tName = Topic $ resource (T.concat ["/publisher/",tName]) []
    
    config = HubbubConfig 1 1 1 localHub
    acidConfig = HubbubAcidConfig . Just

    allDist tq = do
      dist <- atomically $ tryReadTQueue tq
      maybe (return []) (\ d -> (d:) <$> allDist tq) dist 
 
