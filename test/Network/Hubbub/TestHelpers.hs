module Network.Hubbub.TestHelpers
  ( assertRight
  , assertRightEitherT  
  , callback
  , httpTest
  , localCallback
  , localTopic
  , resource
  , scottyServer
  , scottyTest
  , topic
  ) where

import Network.Hubbub.SubscriptionDb 
  ( HttpResource(HttpResource)
  , Topic(Topic)
  , Callback(Callback))

import Prelude (undefined)
import Control.Concurrent (forkIO,killThread)
import Control.Exception (bracket)
import Control.Monad ((=<<),(>>),return)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Either (EitherT,runEitherT)
import Data.Bool (Bool(False))
import Data.Either (Either(Right,Left))
import Data.Function ((.),($),const)
import Data.List ((++))
import Data.Text (append,Text)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import System.IO (IO)
import Test.Tasty.HUnit (Assertion,assertFailure)
import Text.Show (Show,show)
import Web.Scotty (ScottyM,middleware,scotty)

topic :: Text -> Topic
topic n    = Topic $ resource "publish.com" ("/topic/" `append` n)

callback :: Text -> Callback
callback n = Callback $ resource "subscribe.com" ("/callback/" `append` n)

resource :: Text -> Text -> HttpResource
resource host path = HttpResource False host 80 path []

httpTest :: IO () -> Assertion -> Assertion
httpTest server assert = bracket
  (liftIO $ forkIO server)
  killThread
  (const assert)

scottyServer :: ScottyM () -> IO ()
scottyServer = scotty 3000 . (middleware logStdoutDev >>)

scottyTest :: ScottyM () -> Assertion -> Assertion
scottyTest sm = httpTest (scottyServer sm)   

localTopic :: [(Text,Text)] -> Topic
localTopic = Topic . HttpResource False "localhost" 3000 "topic"

localCallback :: [(Text,Text)] -> Callback
localCallback = Callback . HttpResource False "localhost" 3000 "callback"

assertRight :: Show e => Either e a -> IO a
assertRight (Left e)  = do
  assertFailure $ "Expecting right but got left: " ++ show e
  return undefined -- TODO: There must be a better way. 
  
assertRight (Right a) = return a 

assertRightEitherT :: Show e => EitherT e IO a -> IO a
assertRightEitherT = (assertRight =<<) . runEitherT 
