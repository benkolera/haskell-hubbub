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
  , flattenSubs
  , getAllSubscriptions
  , getTopicSubscriptions
  , removeSubscription
  ) where

import Network.Hubbub.SubscriptionDb
  ( Callback
  , From 
  , HttpResource
  , Secret
  , Subscription(Subscription)
  , SubscriptionDbApi(SubscriptionDbApi)
  , Topic )

import Control.Applicative((<$>))
import Control.Error (syncIO)
import Control.Monad (return,mapM_)
import Control.Monad.Reader(ask)
import Control.Monad.State(modify,get,put)
import Data.Acid
  ( AcidState
  , Query
  , Update
  , closeAcidState
  , openLocalState
  , openLocalStateFrom
  , update
  , query
  , makeAcidic
  , liftQuery )
import Data.Eq (Eq)
import Data.Function ((.),($),const)
import Data.Functor (fmap)
import Data.List (filter)
import Data.Map (Map,assocs,findWithDefault,empty,alter,insert,adjust)
import Data.Maybe(Maybe(Just,Nothing),fromMaybe,maybe)
import Data.Ord ((>))
import Data.SafeCopy (deriveSafeCopy,base)
import Data.Time(UTCTime)
import Data.Typeable (Typeable)
import System.IO (IO,FilePath)
import Text.Show (Show)

--------------------------------------------------------------------------------
-- Derive safecopy instances for our data --------------------------------------
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- AcidState Transactions ------------------------------------------------------
--------------------------------------------------------------------------------

getTopicSubscriptions :: Topic -> Query SubscriptionDb TopicSubscriptions
getTopicSubscriptions t =
  findWithDefault empty t . allSubscriptions <$> ask

getAllSubscriptions :: Query SubscriptionDb [(Topic,Callback,Subscription)]
getAllSubscriptions = flattenSubs . allSubscriptions <$> ask

expireSubscriptions :: UTCTime -> Update SubscriptionDb ()
expireSubscriptions now = do
  subs <- liftQuery getAllSubscriptions
  mapM_ remove . filter ((now >) . expiresAt) $ subs
  where
    remove (t,cb,_) = removeSubscription t cb
    expiresAt (_,_,Subscription _ e _ _) = e

flattenSubs :: Map Topic TopicSubscriptions -> [(Topic,Callback,Subscription)]
flattenSubs m = do
  (t,subs) <- assocs m
  (c,s)    <- assocs subs
  return (t,c,s)

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
  ,'expireSubscriptions
  ])

--------------------------------------------------------------------------------
-- Api Implementation ----------------------------------------------------------
--------------------------------------------------------------------------------

acidDbApi :: Maybe FilePath -> IO SubscriptionDbApi
acidDbApi fp = do
  acid <- maybe openLocalState openLocalStateFrom fp emptyDb
  let
    add t cb sb = syncIO . update acid $ AddSubscription t cb sb
    remove t cb = syncIO . update acid $ RemoveSubscription t cb
    getSubs t   = fmap assocs . syncIO . query  acid $ GetTopicSubscriptions t
    allSubs     = syncIO . query acid $ GetAllSubscriptions
    expire now  = syncIO . update acid $ ExpireSubscriptions now
    shutdown    = closeAcidState acid
  return $ SubscriptionDbApi add remove getSubs allSubs expire shutdown        

--------------------------------------------------------------------------------
