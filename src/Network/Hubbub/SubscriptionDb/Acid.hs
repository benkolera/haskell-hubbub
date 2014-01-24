{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE DeriveDataTypeable, TypeFamilies, TemplateHaskell #-}

module Network.Hubbub.SubscriptionDb.Acid
  ( AddSubscription (AddSubscription)
  , RemoveSubscription (RemoveSubscription)  
  , GetTopicSubscriptions(GetTopicSubscriptions)
  , SubscriptionDb (SubscriptionDb)
  , addSubscription
  , acidDbApi
  , allSubscriptions
  , emptyDb
  , getAllSubscriptions
  , getTopicSubscriptions
  , removeSubscription
  ) where

import Network.Hubbub.SubscriptionDb
  ( Callback
  , From 
  , HttpResource
  , Secret
  , Subscription
  , SubscriptionDbApi(SubscriptionDbApi)
  , Topic )

import Control.Applicative((<$>))
import Control.Error (syncIO)
import Control.Monad (return)
import Control.Monad.Reader(ask)
import Control.Monad.State(modify,get,put)
import Data.Acid (AcidState,Query,Update,closeAcidState,update,query,makeAcidic)
import Data.Function ((.),($),const)
import Data.Functor (fmap)
import Data.Eq (Eq)
import Data.Maybe(Maybe(Just,Nothing),fromMaybe)
import Data.Map (Map,assocs,findWithDefault,empty,alter,insert,adjust)
import Data.SafeCopy (deriveSafeCopy,base)
import Text.Show (Show)
import Data.Typeable (Typeable)

$(deriveSafeCopy 0 'base ''HttpResource)
$(deriveSafeCopy 0 'base ''Topic)
$(deriveSafeCopy 0 'base ''Callback)
$(deriveSafeCopy 0 'base ''Secret)
$(deriveSafeCopy 0 'base ''From)
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

acidDbApi :: AcidState SubscriptionDb -> SubscriptionDbApi
acidDbApi acid = SubscriptionDbApi add remove getSubs shutdown
  where
    add t cb sb = syncIO . update acid $ AddSubscription t cb sb
    remove t cb = syncIO . update acid $ RemoveSubscription t cb
    getSubs t   = fmap assocs . syncIO . query  acid $ GetTopicSubscriptions t
    shutdown    = closeAcidState acid
