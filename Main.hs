module Main where

import Network.Hubbub
  ( Callback(Callback)
  , From(From)
  , HttpResource(HttpResource)
  , HubbubConfig(HubbubConfig)
  , HubbubSqLiteConfig(HubbubSqLiteConfig)
  , HubbubEnv
  , LeaseSeconds(LeaseSeconds)
  , Secret(Secret)
  , ServerUrl(ServerUrl)
  , Topic(Topic)
  , Subscription(Subscription)
  , initializeHubbubSqLite
  , httpResourceFromText
  , httpResourceToText
  , listSubscriptions
  , shutdownHubbub
  , subscribe
  , unsubscribe
  , publish )

import Prelude (Int)
import Control.Applicative ((<$>),(<*>))
import Control.Error (either,runEitherT)
import Control.Monad (return,(=<<))
import Control.Monad.IO.Class (liftIO)
import Data.Bool (Bool(False))
import Data.Functor (fmap)
import Data.Function (($),(.),const)
import Data.Maybe (Maybe(Nothing,Just),maybe,fromMaybe)
import Data.String (String)
import qualified Data.Text.Lazy as TL
import Network.HTTP.Types.Status (status400,status202,status500)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import System.IO (IO)
import Text.Show (show)

import Web.Scotty
  ( ActionM
  , Parsable
  , get
  , middleware
  , html
  , param
  , post
  , rescue
  , reqHeader
  , scotty
  , status
  , text )

--------------------------------------------------------------------------------
-- Define routes & setup hubbub ------------------------------------------------
--------------------------------------------------------------------------------

port :: Int
port = 5000

main :: IO ()
main = do
  hubbub <- initializeHubbubSqLite hubbubConf hubbubSqLiteConfig
  scotty port (scottyM hubbub)
  shutdownHubbub hubbub

  where
    scottyM hubbub = do
      middleware logStdoutDev
      get "/subscriptions"  $ listSubscriptionHandler hubbub
      post "/subscriptions" $ doSubscriptionHandler hubbub
      post "/publish"       $ publishHandler hubbub

    hubbubConf         = HubbubConfig 1 1 1 serverUrl defaultLeaseTmOut
    hubbubSqLiteConfig = HubbubSqLiteConfig . Just $ "/tmp/hubbub.db"
    defaultLeaseTmOut  = LeaseSeconds 1800
    serverUrl          = ServerUrl (HttpResource False "localhost" port "" [])

--------------------------------------------------------------------------------
-- ListSubscription ActionM ----------------------------------------------------
--------------------------------------------------------------------------------

listSubscriptionHandler :: HubbubEnv -> ActionM ()
listSubscriptionHandler env = do
  subEither <- liftIO . runEitherT $ listSubscriptions env
  either
    error
    (html . TL.concat . fmap subToLine)
    subEither
  where
    error err = do
      status status500
      text (TL.pack $ show err)
    subToLine (Topic t,Callback cb,Subscription st ex sec from) =
      TL.intercalate " "
      [ "<p>Topic:"
      , TL.fromStrict $ httpResourceToText t
      , "Callback:"
      , TL.fromStrict $ httpResourceToText cb
      , "Started at:"
      , TL.pack . show $ st
      , "Expires at:"
      , TL.pack . show $ ex
      , "Secret:"
      , maybe "NONE" maskSecret sec
      , "From:"
      , maybe "NONE" (\ (From f) -> TL.fromStrict f) from
      , "</p>" ]

    maskSecret (Secret sec) = TL.map (const '*') . TL.fromStrict $ sec

--------------------------------------------------------------------------------
-- DoSubscription ActionM ------------------------------------------------------
--------------------------------------------------------------------------------

data Mode = Subscribe | Unsubscribe

doSubscriptionHandler :: HubbubEnv -> ActionM ()
doSubscriptionHandler env = do
  mode <- (parseMode =<<) <$> optionalParam "hub.mode"
  top  <- topicParam
  cb   <- callbackParam

  fromMaybe (badRequest "") $ doSubscription <$> mode <*> top <*> cb

  where
    parseMode :: String -> Maybe Mode
    parseMode "subscribe"   = Just Subscribe
    parseMode "unsubscribe" = Just Unsubscribe
    parseMode _             = Nothing

    doSubscription Subscribe   = doSubscribe
    doSubscription Unsubscribe = doUnsubscribe

    doSubscribe top cb = do
      ls   <- fmap LeaseSeconds <$> optionalParam "hub.lease_seconds"
      sec  <- fmap Secret  <$> optionalParam "hub.secret"
      from <- fmap (From . TL.toStrict) <$> reqHeader "From"
      liftIO $ subscribe env top cb ls sec from
      status status202

    doUnsubscribe top cb = do
      liftIO $ unsubscribe env top cb
      status status202

--------------------------------------------------------------------------------
-- DoPublish ActionM
--------------------------------------------------------------------------------

publishHandler :: HubbubEnv -> ActionM ()
publishHandler hubbub = do
  topic <- topicParam
  maybe (badRequest "Invalid topic") (liftIO . publish hubbub) topic

--------------------------------------------------------------------------------
-- Parsing Parameters ----------------------------------------------------------
--------------------------------------------------------------------------------

topicParam :: ActionM (Maybe Topic)
topicParam = fmap Topic <$> httpResourceParam "hub.topic"

callbackParam :: ActionM (Maybe Callback)
callbackParam = fmap Callback <$> httpResourceParam "hub.callback"

httpResourceParam :: TL.Text -> ActionM (Maybe HttpResource)
httpResourceParam = fmap (httpResourceFromText . TL.toStrict =<<) . optionalParam

optionalParam :: Parsable a => TL.Text -> ActionM (Maybe a)
optionalParam n = fmap Just (param n) `rescue` const (return Nothing)

require :: TL.Text -> Maybe a -> ActionM ()
require msg = maybe (badRequest msg) (const $ return ())

badRequest :: TL.Text -> ActionM ()
badRequest msg = do
  status status400
  text msg
