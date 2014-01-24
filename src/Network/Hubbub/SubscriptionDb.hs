{-# LANGUAGE DeriveDataTypeable #-}

module Network.Hubbub.SubscriptionDb
  ( Callback (Callback)
  , From (From)
  , HttpResource (HttpResource)
  , Secret (Secret)
  , Subscription (Subscription)
  , SubscriptionDbApi(SubscriptionDbApi)
  , Topic (Topic)
  , addSubscription
  , removeSubscription
  , getTopicSubscriptions
  , fromCallback
  , fromFrom
  , fromSecret
  , fromTopic
  , httpResourceQueryString    
  , httpResourceToText
  , shutdownDb
  ) where

import Prelude (Integer,Int,String,toInteger)
import Control.Arrow ((***))
import Control.Error (EitherT)
import Control.Exception.Base (SomeException)
import Control.Monad (join)
import Data.Bool (Bool)
import Data.Function ((.),($))
import Data.Eq (Eq)
import Data.Maybe(Maybe(Just))
import Data.List (map)
import Data.Ord (Ord)
import Text.Show (Show)
import Data.Time(UTCTime)
import Data.Typeable (Typeable)
import Data.Text(Text,unpack,pack)
import Network.URL
  ( URL(URL)
  , URLType(Absolute)
  , Host(Host)
  , Protocol(HTTP)
  , exportParams
  , exportURL )
import System.IO (IO)  

-- | Bottles up all of the things we need to make a HTTP request to either the
--   Publishing server or the subscriber.     
data HttpResource = 
  HttpResource 
    Bool            -- ^ Is Secure
    Text            -- ^ Host
    Int             -- ^ Port
    Text            -- ^ Path    
    [(Text,Text)]   -- ^ QueryParams
    deriving (Eq,Show,Typeable,Ord)

httpResourceToText :: HttpResource -> Text
httpResourceToText (HttpResource sec h prt pth qps) =
  pack . exportURL $ URL urlType (unpack pth) queryParams
  where
    urlType :: URLType
    urlType = Absolute $ Host (HTTP sec) (unpack h) (Just . toInteger $ prt)
    queryParams :: [(String,String)]
    queryParams = map (join (***) unpack) qps

httpResourceQueryString :: HttpResource -> Text
httpResourceQueryString (HttpResource _ _ _ _ qps ) =
  pack . exportParams . map (join (***) unpack) $ qps

newtype Topic = Topic HttpResource deriving (Show,Typeable,Ord,Eq)
fromTopic :: Topic -> HttpResource
fromTopic (Topic t) = t  

newtype Callback = Callback HttpResource deriving (Show,Typeable,Ord,Eq)
fromCallback :: Callback -> HttpResource
fromCallback (Callback t) = t

newtype Secret = Secret Text deriving (Show,Typeable,Ord,Eq)
fromSecret :: Secret -> Text
fromSecret (Secret t) = t  

newtype From = From Text deriving (Show,Typeable,Ord,Eq)
fromFrom :: From -> Text
fromFrom (From t) = t    

data Subscription = Subscription
  UTCTime         -- ^ StartedAt
  UTCTime         -- ^ ExpiresAt
  (Maybe Secret)  -- ^ Secret
  (Maybe From)    -- ^ From
  deriving (Show,Typeable,Eq)

type SubscriptionDbApiResult = EitherT SomeException IO
data SubscriptionDbApi = SubscriptionDbApi {
  addSubscription ::
     Topic -> Callback -> Subscription -> SubscriptionDbApiResult ()
  , removeSubscription ::
     Topic -> Callback -> SubscriptionDbApiResult ()
  , getTopicSubscriptions ::
     Topic -> SubscriptionDbApiResult [(Callback,Subscription)]
  , shutdownDb :: IO ()
  }

