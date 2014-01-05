{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE DeriveDataTypeable, TypeFamilies, TemplateHaskell #-}

module Network.Hubbub.SubscriptionDb where

import Control.Monad.State(modify,get,put)
import Control.Monad.Reader(ask)
import Control.Applicative((<$>))
import Data.Acid (Query,Update,makeAcidic)
import Data.Typeable (Typeable)
import Data.SafeCopy (deriveSafeCopy,base)
import Data.Time(UTCTime)
import Data.Maybe(fromMaybe)
import qualified Data.Map as Map
import Data.Text(Text)
import Network.URL(URL,URLType,Host,Protocol)


$(deriveSafeCopy 0 'base ''Protocol)
$(deriveSafeCopy 0 'base ''Host)
$(deriveSafeCopy 0 'base ''URLType)
$(deriveSafeCopy 0 'base ''URL)

newtype Topic = Topic URL deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''Topic)

newtype Callback = Callback URL deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''Callback)

newtype Secret = Secret Text deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''Secret)
  
newtype From = From Text deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''From)
  
data Subscription = Subscription {
  startedAt :: UTCTime
  , expiresAt :: Maybe UTCTime
  , secret :: Maybe Secret
  , from :: Maybe From
  } deriving (Show,Typeable,Eq)

$(deriveSafeCopy 0 'base ''Subscription)

type TopicSubscriptions = Map.Map Callback Subscription
             
data SubscriptionDb = SubscriptionDb {
  allSubscriptions :: Map.Map Topic TopicSubscriptions
  } deriving (Typeable,Show,Eq)
$(deriveSafeCopy 0 'base ''SubscriptionDb)

emptyDb :: SubscriptionDb
emptyDb = SubscriptionDb Map.empty
  
getAllSubscriptions :: Query SubscriptionDb (Map.Map Topic TopicSubscriptions)
getAllSubscriptions = allSubscriptions <$> ask 

getTopicSubscriptions :: Topic -> Query SubscriptionDb TopicSubscriptions
getTopicSubscriptions t =
  Map.findWithDefault Map.empty t . allSubscriptions <$> ask

addSubscription :: Topic -> Callback -> Subscription -> Update SubscriptionDb ()
addSubscription t u s = modify add
  where
   add (SubscriptionDb m) = SubscriptionDb $ Map.alter (Just . updateTopicSubs) t m
   updateTopicSubs = Map.insert u s . fromMaybe Map.empty

removeSubscription :: Topic -> Callback -> Update SubscriptionDb (Maybe Subscription)
removeSubscription t u = do
  (SubscriptionDb m) <- get
  put . SubscriptionDb $ Map.adjust (Map.alter (const Nothing) u) t m 
  return $ Map.lookup t m >>= Map.lookup u

$(makeAcidic ''SubscriptionDb [
  'getAllSubscriptions
  ,'getTopicSubscriptions
  ,'addSubscription
  ])
