{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE DeriveDataTypeable, TypeFamilies, TemplateHaskell #-}

module Network.Hubbub.SubscriptionDb
  ( AddSubscription (AddSubscription)
  , RemoveSubscription (RemoveSubscription)  
  , Callback (Callback)
  , GetTopicSubscriptions(GetTopicSubscriptions)
  , From (From)  
  , HttpResource (HttpResource)
  , Secret (Secret)
  , Subscription (Subscription)
  , SubscriptionDb (SubscriptionDb)
  , Topic (Topic)
  , addSubscription    
  , allSubscriptions
  , emptyDb
  , fromCallback
  , fromFrom
  , fromSecret
  , fromTopic
  , getAllSubscriptions
  , getTopicSubscriptions
  , httpResourceQueryString    
  , httpResourceToText
  , removeSubscription
  ) where

import Prelude (Integer,Int,String,toInteger)
import Control.Applicative((<$>))
import Control.Arrow ((***))
import Control.Monad (return,join)
import Control.Monad.Reader(ask)
import Control.Monad.State(modify,get,put)
import Data.Acid (Query,Update,makeAcidic)
import Data.Bool (Bool)
import Data.Function ((.),($),const)
import Data.Eq (Eq)
import Data.Maybe(Maybe(Just,Nothing),fromMaybe)
import Data.List (map)
import Data.Map (Map,findWithDefault,empty,alter,insert,adjust)
import Data.Ord (Ord)
import Data.SafeCopy (deriveSafeCopy,base)
import Text.Show (Show)
import Data.Time(UTCTime)
import Data.Typeable (Typeable)
import Data.Text(Text,unpack,pack)
import Network.URL 

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

$(deriveSafeCopy 0 'base ''HttpResource)

newtype Topic = Topic HttpResource deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''Topic)
fromTopic :: Topic -> HttpResource
fromTopic (Topic t) = t  

newtype Callback = Callback HttpResource deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''Callback)
fromCallback :: Callback -> HttpResource
fromCallback (Callback t) = t    

newtype Secret = Secret Text deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''Secret)
fromSecret :: Secret -> Text
fromSecret (Secret t) = t  
  
newtype From = From Text deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''From)
fromFrom :: From -> Text
fromFrom (From t) = t    
  
data Subscription = Subscription
  UTCTime         -- ^ StartedAt
  UTCTime         -- ^ ExpiresAt
  (Maybe Secret)  -- ^ Secret
  (Maybe From)    -- ^ From
  deriving (Show,Typeable,Eq)

$(deriveSafeCopy 0 'base ''Subscription)

type TopicSubscriptions = Map Callback Subscription

data SubscriptionDb = SubscriptionDb {
  allSubscriptions :: Map Topic TopicSubscriptions
  } deriving (Typeable,Show,Eq)
$(deriveSafeCopy 0 'base ''SubscriptionDb)

emptyDb :: SubscriptionDb
emptyDb = SubscriptionDb empty

getAllSubscriptions :: Query SubscriptionDb (Map Topic TopicSubscriptions)
getAllSubscriptions = allSubscriptions <$> ask 

getTopicSubscriptions :: Topic -> Query SubscriptionDb TopicSubscriptions
getTopicSubscriptions t =
  findWithDefault empty t . allSubscriptions <$> ask

addSubscription :: Topic -> Callback -> Subscription -> Update SubscriptionDb ()
addSubscription t u s = modify add
  where
   add (SubscriptionDb m) = SubscriptionDb $ alter (Just . updateTopicSubs) t m
   updateTopicSubs = insert u s . fromMaybe empty

removeSubscription :: Topic -> Callback -> Update SubscriptionDb ()
removeSubscription t u = do
  (SubscriptionDb m) <- get
  put . SubscriptionDb $ adjust (alter (const Nothing) u) t m 
  return ()

$(makeAcidic ''SubscriptionDb [
  'getAllSubscriptions
  ,'getTopicSubscriptions
  ,'addSubscription
  ,'removeSubscription
  ])
