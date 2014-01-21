module Network.Hubbub.Http.Test (httpSuite) where

import Network.Hubbub.Http
  ( HttpError(NotFound,ServerError,NotOk)
  , ServerUrl (ServerUrl)
  , checkSubscription
  , getPublishedResource
  , publishResource )

import Network.Hubbub.Queue 
  ( SubscriptionEvent(SubscriptionEvent) 
  , Mode (SubscribeMode))
import Network.Hubbub.SubscriptionDb 
  ( Topic (Topic)
  , Callback (Callback)
  , HttpResource(HttpResource)
  , Secret(Secret))
import Network.Hubbub.TestHelpers ()

import Prelude (undefined,Int,putStrLn)
import Control.Applicative ((<$>),liftA2)
import Control.Arrow ((***))
import Control.Concurrent (forkIO,killThread)
import Control.Exception (bracket)
import Control.Monad ((>>=),(>>),unless,join,return)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Either (runEitherT)
import Data.Either (Either(Left,Right))
import Data.Bool (Bool(True,False),(||))
import qualified Data.ByteString      as Bs
import qualified Data.ByteString.Lazy as BsL 
import Data.Eq ((==))
import Data.Function (const,($),(.))
import Data.Functor (fmap)
import Data.List ((++),filter)
import Data.Maybe (Maybe(Nothing,Just))
import qualified Data.Text.Lazy as TL
import Data.Text (Text)
import Data.Tuple (fst)
import Network.HTTP.Types.Status (status404,status500,status400)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import System.IO (IO)
import System.Random (getStdGen)
import Test.Tasty (testGroup, TestTree)
import Test.Tasty.HUnit (Assertion,testCase,(@?=),assertFailure)
import Text.Show (Show,show)
import Web.Scotty
  ( Parsable
  , ActionM
  , ScottyM
  , body  
  , get
  , middleware
  , next
  , param
  , params
  , post
  , raise
  , reqHeader
  , rescue
  , scotty
  , status
  , text )

httpSuite :: TestTree
httpSuite = testGroup "Http" 
  [getPublishedResourceSuite,checkSubscriptionSuite,publishResourceSuite]

--------------------------------------------------------------------------------
-- GetPublishedResourceSuite
--------------------------------------------------------------------------------

getPublishedResourceSuite :: TestTree
getPublishedResourceSuite = testGroup "GetPublishedResource"
  [ testCase "basic" okGetPublishedResource
  , testCase "404"   notFoundGetPublishedResource
  , testCase "500"   serverErrorGetPublishedResource
  , testCase "notOk" notOkGetPublishedResource]

okGetPublishedResource :: Assertion
okGetPublishedResource = scottyTest scottyM $ do
  (t,c) <- runGetPublishedResource $ localTopic []
  t @?= Just "text/plain"
  c @?= "Hello world!"
  where
    scottyM = get "/topic" $ text "Hello world!"

notFoundGetPublishedResource :: Assertion
notFoundGetPublishedResource = scottyTest (return ()) $ do
  either <- runEitherT (getPublishedResource $ localTopic [])
  assertError either
  where
    assertError (Left (NotFound _)) = return ()
    assertError res = assertFailure $ "Expected not found but got: " ++ show res

notOkGetPublishedResource :: Assertion
notOkGetPublishedResource = scottyTest scottyM $ do
  either <- runEitherT (getPublishedResource $ localTopic [])
  assertError either
  where
    scottyM = get "/topic" $ status status400
    assertError (Left (NotOk _ c s)) = do
      c @?= 400
      s @?= "Bad Request"
    assertError res = assertFailure $ "Expected not found but got: " ++ show res

serverErrorGetPublishedResource :: Assertion
serverErrorGetPublishedResource = scottyTest scottyM $ do
  either <- runEitherT (getPublishedResource $ localTopic [])
  assertError either
  where
    scottyM = get "/topic" $ status status500
    assertError (Left (ServerError _ res)) = res @?= "Internal Server Error"
    assertError res = assertFailure $ "Expected ServerErr but got: " ++ show res

runGetPublishedResource :: Topic -> IO (Maybe Bs.ByteString,BsL.ByteString)
runGetPublishedResource t = runEitherT (getPublishedResource t) >>= assertRight

--------------------------------------------------------------------------------
-- CheckSubscriptionSuite
--------------------------------------------------------------------------------

checkSubscriptionSuite :: TestTree
checkSubscriptionSuite = testGroup "CheckSubscription"
  [ testCase "basic"                  basicCheckSubscriptionTest
  , testCase "keep params"            keepParamsCheckSubscriptionTest  
  , testCase "fail verify"            failVerifySubscriptionTest
  , testCase "bad challenge response" badChallengeVerifySubscriptionTest ]

callbackTest :: CallbackHandler -> Assertion -> Assertion
callbackTest handler = scottyTest (callbackM handler)
  
basicCheckSubscriptionTest :: Assertion
basicCheckSubscriptionTest = callbackTest handleCallback $ do
  res <- runCheckSubscription event
  res @?= True
  where
    handleCallback "subscribe" "http://localhost:3000/topic" c _ = text c
    handleCallback _ _ _ _ = status status404
    event = SubscriptionEvent
            (localTopic [])
            (localCallback [])
            SubscribeMode
            Nothing
            Nothing
            Nothing

keepParamsCheckSubscriptionTest :: Assertion
keepParamsCheckSubscriptionTest = callbackTest handleCallback $ do
  res <- runCheckSubscription event
  res @?= True
  where
    handleCallback
      "subscribe"
      "http://localhost:3000/topic?paramA=1&paramB=foo+bar&paramA=2"
      c
      _
      = do
        -- TODO: This is a bit crap. But the Parsable [a] instance doesn't grab
        -- both out. (pAs <- param "pA" :: ActionM [Int] results in pAs = [13])
        ps <- filter (liftA2 (||) (== "pA") (== "pB") . fst) <$> params
        unless (ps == fmap (join (***) TL.fromStrict) topicParams) $ do
          liftIO . putStrLn $ show ps
          raise "ParamA and ParamB didn't match"
        text c
    handleCallback _ _ _ _ = status status404
    event = SubscriptionEvent
            (localTopic [("paramA","1"),("paramB","foo bar"),("paramA","2")])
            (localCallback topicParams)
            SubscribeMode
            Nothing
            Nothing
            Nothing
    topicParams = [("pA","13"),("pA","37"),("pB","a b"),("pB","b c")]

failVerifySubscriptionTest :: Assertion
failVerifySubscriptionTest = callbackTest handleCallback $ do
  res <- runCheckSubscription event
  res @?= False
  where
    handleCallback _ _ _ _ = status status404
    event = SubscriptionEvent
            (localTopic [])
            (localCallback [])
            SubscribeMode
            Nothing
            Nothing
            Nothing

badChallengeVerifySubscriptionTest :: Assertion
badChallengeVerifySubscriptionTest = callbackTest handleCallback $ do
  res <- runCheckSubscription event
  res @?= False
  where
    handleCallback _ _ _ _ = text "not a valid challenge response"
    event = SubscriptionEvent
            (localTopic [])
            (localCallback [])
            SubscribeMode
            Nothing
            Nothing
            Nothing            

runCheckSubscription :: SubscriptionEvent -> IO Bool
runCheckSubscription e = do
  rng <- getStdGen
  runEitherT (checkSubscription rng e) >>= assertRight

--------------------------------------------------------------------------------
-- PublishResourceSuite
--------------------------------------------------------------------------------

publishResourceSuite :: TestTree
publishResourceSuite = testGroup "PublishResource"
  [ testCase "basic"            basicPublishResourceTest
  , testCase "hmaced"           hmacPublishResourceTest
  , testCase "callback failure" failPublishResourceTest
  ]

publishTest :: PublishHandler -> Assertion -> Assertion
publishTest handler = scottyTest (publishM handler)

basicPublishResourceTest :: Assertion
basicPublishResourceTest = publishTest handlePublish $ 
  runPublishResource
    Nothing
    (localCallback [])
    (localTopic [])
    localHub
    (Just "text/html")
    "foobar"
  where
    handlePublish :: PublishHandler
    handlePublish (Just "text/html") Nothing l "foobar" = do
      unless (l == Just expectedLink) next
      return ()
    handlePublish _ _ _ _ = status status500
    expectedLink =
      "<http://localhost:3000/topic>; rel=\"self\",<http://localhost:3000/hub>; rel=\"hub\""

hmacPublishResourceTest :: Assertion
hmacPublishResourceTest = publishTest handlePublish $ 
  runPublishResource
    (Just $ Secret "supersecretsquirrel")
    (localCallback [])
    (localTopic [])
    localHub
    (Just "text/html")
    "foobar"
  where
    handlePublish :: PublishHandler
    handlePublish (Just "text/html") (Just sig) (Just l) "foobar" = do
      unless (l == expectedLink) next
      unless (sig == expectedSig) next
      return ()
    handlePublish _ _ _ _ = status status500
    expectedSig  = "1ec8409d5244edbabb92624575e9b1b2f1485dbb"
    expectedLink = 
      "<http://localhost:3000/topic>; rel=\"self\",<http://localhost:3000/hub>; rel=\"hub\""


failPublishResourceTest :: Assertion
failPublishResourceTest = publishTest handlePublish $ do
  pubEither <- runEitherT $ publishResource
    Nothing
    (localCallback [])
    (localTopic [])
    localHub
    (Just "text/html")
    "foobar"
  assertError pubEither
  where
    handlePublish _ _ _ _ = status status404
    assertError (Left (NotFound _)) = return ()
    assertError res = assertFailure $ "Expected NotFound but got: " ++ show res 

runPublishResource ::
  Maybe Secret ->
  Callback ->
  Topic ->
  ServerUrl ->
  Maybe Bs.ByteString ->
  BsL.ByteString ->
  IO ()
runPublishResource s cb top surl mt b = do
  e <- runEitherT (publishResource s cb top surl mt b)
  assertRight e

---- 

assertRight :: Show e => Either e a -> IO a
assertRight (Left e)  = do
  assertFailure $ "Expecting right but got left: " ++ show e
  return undefined -- TODO: There must be a better way. 
  
assertRight (Right a) = return a 

localTopic :: [(Text,Text)] -> Topic
localTopic = Topic . HttpResource False "localhost" 3000 "topic"

localCallback :: [(Text,Text)] -> Callback
localCallback = Callback . HttpResource False "localhost" 3000 "callback"

localHub :: ServerUrl
localHub = ServerUrl $ HttpResource False "localhost" 3000 "hub" []

optParam :: Parsable a => TL.Text -> ActionM (Maybe a)
optParam label = fmap Just (param label) `rescue` const (return Nothing)

type CallbackHandler = TL.Text -> TL.Text -> TL.Text -> Maybe Int -> ActionM ()

callbackM :: CallbackHandler -> ScottyM ()
callbackM cbAction = 
  get "/callback" $ do
    mode      <- param "hub.mode"
    topic     <- param "hub.topic"
    challenge <- param "hub.challenge"
    ls        <- optParam "hub.leaseSeconds"
    cbAction mode topic challenge ls

type PublishHandler =
  Maybe TL.Text ->
  Maybe TL.Text ->
  Maybe TL.Text ->
  BsL.ByteString ->
  ActionM ()

publishM :: PublishHandler -> ScottyM ()
publishM pubAction = 
  post "/callback" $ do
    ct  <- reqHeader "Content-Type"    
    sig <- reqHeader "X-Hub-Signature"
    l   <- reqHeader "Link"
    b   <- body
    pubAction ct sig l b

httpTest :: IO () -> Assertion -> Assertion
httpTest server assert = bracket
  (liftIO $ forkIO server)
  killThread
  (const assert)

scottyServer :: ScottyM () -> IO ()
scottyServer = scotty 3000 . (middleware logStdoutDev >>)

scottyTest :: ScottyM () -> Assertion -> Assertion
scottyTest sm = httpTest (scottyServer sm) 
