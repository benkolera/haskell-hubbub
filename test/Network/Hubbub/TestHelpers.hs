module Network.Hubbub.TestHelpers
  ( assertRight
  , assertRightEitherT  
  , callback
  , httpTest
  , localHub
  , localCallback
  , localTopic
  , resource
  , scottyServer
  , scottyTest
  , scottyTestWithShutdown
  , subscription
  , topic
  ) where

import Network.Hubbub.Http (ServerUrl(ServerUrl))

import Network.Hubbub.SubscriptionDb 
  ( HttpResource(HttpResource)
  , Topic(Topic)
  , Callback(Callback)
  , From(From)
  , Subscription(Subscription) )

import Prelude (undefined)
import Control.Concurrent (forkIO,killThread)
import Control.Exception (bracket)
import Control.Monad ((=<<),(>>),return)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Either (EitherT,runEitherT)
import Data.Bool (Bool(False))
import Data.DateTime (addSeconds)
import Data.Either (Either(Right,Left))
import Data.Function ((.),($),const,flip)
import Data.List ((++))
import Data.Maybe (Maybe(Nothing,Just))
import Data.Text (append,Text)
import Data.Time (UTCTime)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import System.IO (IO)
import Test.Tasty.HUnit (Assertion,assertFailure)
import Text.Show (Show,show)
import Web.Scotty (ScottyM,middleware,scotty)

topic :: Text -> Topic
topic n = Topic $ resource ("/topic/" `append` n) []

callback :: Text -> Callback
callback n = Callback $ resource ("/callback/" `append` n) []

resource :: Text -> [(Text,Text)] -> HttpResource
resource = HttpResource False "localhost" 3000

httpTest :: IO () -> IO() -> Assertion -> Assertion
httpTest server shutdown assert = bracket
  (liftIO $ forkIO server)
  ((shutdown >>) . killThread)
  (const assert)

scottyServer :: ScottyM () -> IO ()
scottyServer = scotty 3000 . (middleware logStdoutDev >>)

scottyTest :: ScottyM () -> Assertion -> Assertion
scottyTest = flip scottyTestWithShutdown (return ())

scottyTestWithShutdown :: ScottyM () -> IO () -> Assertion -> Assertion
scottyTestWithShutdown sm = httpTest (scottyServer sm) 

localTopic :: [(Text,Text)] -> Topic
localTopic = Topic . resource "topic"

localCallback :: [(Text,Text)] -> Callback
localCallback = Callback . resource "callback"

localHub :: ServerUrl
localHub = ServerUrl $ HttpResource False "localhost" 3000 "hub" []

assertRight :: Show e => Either e a -> IO a
assertRight (Left e)  = do
  assertFailure $ "Expecting right but got left: " ++ show e
  return undefined -- TODO: There must be a better way. 
  
assertRight (Right a) = return a 

assertRightEitherT :: Show e => EitherT e IO a -> IO a
assertRightEitherT = (assertRight =<<) . runEitherT 

subscription :: UTCTime -> Text -> Subscription
subscription t n = Subscription t (addSeconds 300 t) Nothing (Just . From $ n)
