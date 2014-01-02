{-# LANGUAGE DeriveDataTypeable, TypeFamilies, TemplateHaskell #-}

module Hubbub.Subscriptions where

import Control.Monad.State(modify)
import Control.Monad.Reader(ask)
import Control.Applicative((<$>))
import Data.Acid
import Data.Typeable
import Data.SafeCopy
import Data.Time(UTCTime)
import Data.Maybe(fromMaybe)
import qualified Data.Map as Map

newtype Topic = Topic String deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''Topic)

newtype CallbackUrl = CallbackUrl String deriving (Show,Typeable,Ord,Eq)
$(deriveSafeCopy 0 'base ''CallbackUrl)

data Subscription = Subscription {
  subscribedAt :: UTCTime
  } deriving (Show,Typeable,Eq)

$(deriveSafeCopy 0 'base ''Subscription)

type TopicSubscriptions = Map.Map CallbackUrl Subscription
             
data SubscriptionDb = SubscriptionDb {
  allSubscriptions :: Map.Map Topic TopicSubscriptions
  } deriving (Typeable,Show,Eq)
$(deriveSafeCopy 0 'base ''SubscriptionDb)

emptyDb :: SubscriptionDb
emptyDb = (SubscriptionDb Map.empty)
  
getAllSubscriptions :: Query SubscriptionDb (Map.Map Topic TopicSubscriptions)
getAllSubscriptions = allSubscriptions <$> ask 

getTopicSubscriptions :: Topic -> Query SubscriptionDb TopicSubscriptions
getTopicSubscriptions t =
  (Map.findWithDefault Map.empty t) . allSubscriptions <$> ask

subscribe :: Topic -> CallbackUrl -> Subscription -> Update SubscriptionDb ()
subscribe t u s = modify go
  where
   go (SubscriptionDb m) = SubscriptionDb $ Map.alter (Just . updateTopicSubs) t m
   updateTopicSubs = (Map.insert u s) . (fromMaybe Map.empty)


$(makeAcidic ''SubscriptionDb [
  'getAllSubscriptions
  ,'getTopicSubscriptions
  ,'subscribe
  ])
