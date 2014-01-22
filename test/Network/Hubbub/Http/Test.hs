module Network.Hubbub.Http.Test (httpSuite) where

import Network.Hubbub.Http
  ( HttpError(NotFound,ServerError,NotOk)
  , verifySubscriptionEvent
  , getPublishedResource
  , distributeResource )

import Network.Hubbub.Queue
  ( AttemptCount(AttemptCount)
  , ContentType(ContentType)
  , DistributionEvent(DistributionEvent)
  , PublicationEvent(PublicationEvent)
  , ResourceBody(ResourceBody)
  , SubscriptionEvent(Subscribe,Unsubscribe)
  , LeaseSeconds(LeaseSeconds))
  
import Network.Hubbub.SubscriptionDb 
  ( Topic
  , Secret(Secret))
import Network.Hubbub.TestHelpers
  ( assertRight
  , scottyTest
  , localHub
  , localTopic
  , localCallback)

import Prelude (undefined,Int,putStrLn)
import Control.Applicative ((<$>),liftA2)
import Control.Arrow ((***))
import Control.Monad ((>>=),unless,join,return)
import Control.Monad.Trans.Either (runEitherT)
import Data.Either (Either(Left))
import Data.Bool (Bool(True,False),(||))
import qualified Data.ByteString.Lazy as BsL 
import Data.Eq ((==))
import Data.Function (const,($),(.))
import Data.Functor (fmap)
import Data.List ((++),filter)
import Data.Maybe (Maybe(Nothing,Just))
import qualified Data.Text.Lazy as TL
import Data.Tuple (fst)
import Network.HTTP.Types.Status (status404,status500,status400)

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
  , next
  , param
  , params
  , post
  , raise
  , reqHeader
  , rescue
  , status
  , text )

httpSuite :: TestTree
httpSuite = testGroup "Http" 
  [ getPublishedResourceSuite
  , verifySubscriptionEventSuite
  , distributeResourceSuite
  ]

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
  (t,c) <- runGetPublishedResource . publicationEvent $ localTopic []
  t @?= (Just $ ContentType "text/plain")
  c @?= ResourceBody "Hello world!"
  where
    scottyM = get "/topic" $ text "Hello world!"

notFoundGetPublishedResource :: Assertion
notFoundGetPublishedResource = scottyTest (return ()) $ do
  either <- runEitherT (getPublishedResource . publicationEvent $ localTopic [])
  assertError either
  where
    assertError (Left (NotFound _)) = return ()
    assertError res = assertFailure $ "Expected not found but got: " ++ show res

notOkGetPublishedResource :: Assertion
notOkGetPublishedResource = scottyTest scottyM $ do
  either <- runEitherT (getPublishedResource . publicationEvent $ localTopic [])
  assertError either
  where
    scottyM = get "/topic" $ status status400
    assertError (Left (NotOk _ c s)) = do
      c @?= 400
      s @?= "Bad Request"
    assertError res = assertFailure $ "Expected not found but got: " ++ show res

serverErrorGetPublishedResource :: Assertion
serverErrorGetPublishedResource = scottyTest scottyM $ do
  either <- runEitherT (getPublishedResource . publicationEvent $ localTopic [])
  assertError either
  where
    scottyM = get "/topic" $ status status500
    assertError (Left (ServerError _ res)) = res @?= "Internal Server Error"
    assertError res = assertFailure $ "Expected ServerErr but got: " ++ show res

publicationEvent :: Topic -> PublicationEvent
publicationEvent t = PublicationEvent t (AttemptCount 1)

runGetPublishedResource ::
  PublicationEvent ->
  IO (Maybe ContentType,ResourceBody)
runGetPublishedResource t = runEitherT (getPublishedResource t) >>= assertRight

--------------------------------------------------------------------------------
-- VerifySubscriptionEventSuite
--------------------------------------------------------------------------------

verifySubscriptionEventSuite :: TestTree
verifySubscriptionEventSuite = testGroup "VerifySubscriptionEvent"
  [ testCase "basic"                  basicVerifySubscriptionEventTest
  , testCase "keep params"            keepParamsVerifySubscriptionEventTest  
  , testCase "fail verify"            failVerifySubscriptionEventTest
  , testCase "bad challenge response" badChallengeVerifySubscriptionEventTest
  , testCase "unsubscribe"            unsubscribeVerifySubscriptionEventTest ]

callbackTest :: CallbackHandler -> Assertion -> Assertion
callbackTest handler = scottyTest (callbackM handler)
  
basicVerifySubscriptionEventTest :: Assertion
basicVerifySubscriptionEventTest = callbackTest handleCallback $ do
  res <- runVerifySubscriptionEvent event
  res @?= True
  where
    handleCallback "subscribe" "http://localhost:3000/topic" c (Just 1337) =
      text c
    handleCallback _ _ _ _ = status status404
    event = Subscribe
            (localTopic [])
            (localCallback [])
            (LeaseSeconds 1337)
            (AttemptCount 1)
            Nothing
            Nothing

unsubscribeVerifySubscriptionEventTest :: Assertion
unsubscribeVerifySubscriptionEventTest = callbackTest handleCallback $ do
  res <- runVerifySubscriptionEvent event
  res @?= True
  where
    handleCallback "unsubscribe" "http://localhost:3000/topic" c Nothing =
      text c
    handleCallback _ _ _ _ = status status404
    event = Unsubscribe (localTopic []) (localCallback []) (AttemptCount 1)

keepParamsVerifySubscriptionEventTest :: Assertion
keepParamsVerifySubscriptionEventTest = callbackTest handleCallback $ do
  res <- runVerifySubscriptionEvent event
  res @?= True
  where
    handleCallback
      "subscribe"
      "http://localhost:3000/topic?paramA=1&paramB=foo+bar&paramA=2"
      c
      (Just 1337)
      = do
        -- TODO: This is a bit crap. But the Parsable [a] instance doesn't grab
        -- both out. (pAs <- param "pA" :: ActionM [Int] results in pAs = [13])
        ps <- filter (liftA2 (||) (== "pA") (== "pB") . fst) <$> params
        unless (ps == fmap (join (***) TL.fromStrict) topicParams) $
          raise "ParamA and ParamB didn't match"
        text c
    handleCallback _ _ _ _ = status status404
    event = Subscribe
            (localTopic [("paramA","1"),("paramB","foo bar"),("paramA","2")])
            (localCallback topicParams)
            (LeaseSeconds 1337)
            (AttemptCount 1)
            Nothing
            Nothing
    topicParams = [("pA","13"),("pA","37"),("pB","a b"),("pB","b c")]

failVerifySubscriptionEventTest :: Assertion
failVerifySubscriptionEventTest = callbackTest handleCallback $ do
  res <- runVerifySubscriptionEvent event
  res @?= False
  where
    handleCallback _ _ _ _ = status status404
    event = Subscribe
            (localTopic [])
            (localCallback [])
            (LeaseSeconds 1337)
            (AttemptCount 1)
            Nothing
            Nothing

badChallengeVerifySubscriptionEventTest :: Assertion
badChallengeVerifySubscriptionEventTest = callbackTest handleCallback $ do
  res <- runVerifySubscriptionEvent event
  res @?= False
  where
    handleCallback _ _ _ _ = text "not a valid challenge response"
    event = Subscribe
            (localTopic [])
            (localCallback [])
            (LeaseSeconds 1337)
            (AttemptCount 1)
            Nothing
            Nothing            

runVerifySubscriptionEvent :: SubscriptionEvent -> IO Bool
runVerifySubscriptionEvent e = do
  rng <- getStdGen
  runEitherT (verifySubscriptionEvent rng e) >>= assertRight

--------------------------------------------------------------------------------
-- DistributeResourceSuite
--------------------------------------------------------------------------------

distributeResourceSuite :: TestTree
distributeResourceSuite = testGroup "DistributeResource"
  [ testCase "basic"            basicDistributeResourceTest
  , testCase "hmaced"           hmacDistributeResourceTest
  , testCase "callback failure" failDistributeResourceTest
  ]

distributeTest :: DistributeHandler -> Assertion -> Assertion
distributeTest handler = scottyTest (distributeM handler)

basicDistributeResourceTest :: Assertion
basicDistributeResourceTest = distributeTest handleDistribute $ 
  runDistributeResource
    Nothing
    (ContentType "text/html")
    (ResourceBody "foobar")
  where
    handleDistribute :: DistributeHandler
    handleDistribute (Just "text/html") Nothing l "foobar" = do
      unless (l == Just expectedLink) next
      return ()
    handleDistribute _ _ _ _ = status status500
    expectedLink =
      "<http://localhost:3000/topic>; rel=\"self\",<http://localhost:3000/hub>; rel=\"hub\""

hmacDistributeResourceTest :: Assertion
hmacDistributeResourceTest = distributeTest handleDistribute $ 
  runDistributeResource
    (Just $ Secret "supersecretsquirrel")
    (ContentType "text/html")
    (ResourceBody "foobar")
  where
    handleDistribute :: DistributeHandler
    handleDistribute (Just "text/html") (Just sig) (Just l) "foobar" = do
      unless (l == expectedLink) next
      unless (sig == expectedSig) next
      return ()
    handleDistribute _ _ _ _ = status status500
    expectedSig  = "1ec8409d5244edbabb92624575e9b1b2f1485dbb"
    expectedLink = 
      "<http://localhost:3000/topic>; rel=\"self\",<http://localhost:3000/hub>; rel=\"hub\""


failDistributeResourceTest :: Assertion
failDistributeResourceTest = distributeTest handleDistribute $ do
  pubEither <- runEitherT $ distributeResource ev localHub
  assertError pubEither
  where
    handleDistribute _ _ _ _ = status status404
    assertError (Left (NotFound _)) = return ()
    assertError res = assertFailure $ "Expected NotFound but got: " ++ show res
    ev = distributionEvent Nothing (ContentType "text/html") (ResourceBody "fo")

runDistributeResource ::
  Maybe Secret ->
  ContentType  ->
  ResourceBody ->
  IO ()
runDistributeResource sec ct rb = do
  e <- runEitherT (distributeResource (distributionEvent sec ct rb) localHub)
  assertRight e

distributionEvent ::
  Maybe Secret ->
  ContentType ->
  ResourceBody ->
  DistributionEvent
distributionEvent sec ct rb =
  DistributionEvent
  (localTopic [])
  (localCallback [])
  (Just ct)
  rb
  sec
  (AttemptCount 1)

---- 



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

type DistributeHandler =
  Maybe TL.Text ->
  Maybe TL.Text ->
  Maybe TL.Text ->
  BsL.ByteString ->
  ActionM ()

distributeM :: DistributeHandler -> ScottyM ()
distributeM distAction = 
  post "/callback" $ do
    ct  <- reqHeader "Content-Type"    
    sig <- reqHeader "X-Hub-Signature"
    l   <- reqHeader "Link"
    b   <- body
    distAction ct sig l b
