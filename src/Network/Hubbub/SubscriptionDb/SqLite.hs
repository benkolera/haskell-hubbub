{-# OPTIONS_GHC -fno-warn-orphans #-}
module Network.Hubbub.SubscriptionDb.SqLite
  ( sqLiteDbApi
  , open
  , withConnection
  , add
  , remove
  , getTopicSubscriptions
  , getAllSubscriptions
  , expireSubscriptions
  ) where

import Network.Hubbub.SubscriptionDb
  ( Callback(Callback)
  , From(From)
  , HttpResource
  , Secret(Secret)
  , Subscription(Subscription)
  , SubscriptionDbApi(SubscriptionDbApi)
  , SubscriptionDbApiResult
  , Topic(Topic)
  , httpResourceFromText
  , httpResourceToText )

import Prelude (undefined)
import Control.Applicative ((<$>),(<*>))
import Control.Error (syncIO)
import Control.Monad ((>>=),return,unless)
import Data.Bool (not)
import Data.Functor (fmap)
import Data.Function ((.),($))
import Data.List (null)
import Data.Maybe (Maybe,maybe,fromMaybe)
import Data.String (String)
import Data.Text (Text)
import Data.Time(UTCTime)
import Database.SQLite.Simple
  ( Connection
  , Only(Only)
  , Query
  , close
  , query
  , query_  
  , execute_
  , execute
  )
import qualified Database.SQLite.Simple as SqL
import Database.SQLite.Simple.Ok (Ok(Ok))
import Database.SQLite.Simple.FromRow (FromRow,fromRow,field)
import Database.SQLite.Simple.ToRow (ToRow,toRow)
import Database.SQLite.Simple.FromField
  ( FromField
  , ResultError(ConversionFailed)
  , fromField
  , returnError )
import Database.SQLite.Simple.ToField (ToField,toField)  
import System.IO (IO,FilePath)


instance FromRow Subscription where
  fromRow = Subscription <$> field <*> field <*> field <*> field

instance ToRow Subscription where
  toRow (Subscription start expire sec from) =
    [toField start,toField expire,toField sec,toField from]

instance FromField Secret where
  fromField = fmap Secret . fromField

instance ToField Secret where
  toField (Secret s) = toField s

instance FromField From where
  fromField = fmap From . fromField

instance ToField From where
  toField (From f) = toField f

instance FromField HttpResource where
  fromField f = fromField f >>= parseHttpResource 
    where
      parseHttpResource t =
        maybe
        (returnError ConversionFailed f "not a valid http resource is not null")
        Ok
        (httpResourceFromText t)

instance ToField HttpResource where
  toField = toField . httpResourceToText

instance FromField Topic where
  fromField = fmap Topic . fromField

instance ToField Topic where
  toField (Topic t) = toField t

instance FromField Callback where
  fromField = fmap Callback . fromField

instance ToField Callback where
  toField (Callback t) = toField t

data SubscriptionRow = SubscriptionRow Topic Callback Subscription

instance FromRow SubscriptionRow where
  fromRow = SubscriptionRow <$> field <*> field <*> fromRow

instance ToRow SubscriptionRow where
  toRow (SubscriptionRow t cb s) = toField t : toField cb : toRow s

open :: String -> IO Connection
open fp = do
  conn <- SqL.open fp
  createSchema conn
  return conn

withConnection :: String -> (Connection -> IO a) -> IO a
withConnection fp f = SqL.withConnection fp $ \conn -> do
  createSchema conn
  f conn

createSchema :: Connection -> IO ()
createSchema conn = do
  t <- query
    conn
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
    (Only ("subscription"::String)) :: IO [Only Text]
  unless (not $ null t) $ 
    execute_ conn ddl
  return ()

sqLiteDbApi :: Maybe FilePath -> IO SubscriptionDbApi
sqLiteDbApi fp = do
  c <- open $ fromMaybe ":memory:" fp 
  return $
    SubscriptionDbApi
    (add c)
    (remove c)
    (getTopicSubscriptions c)
    (getAllSubscriptions c)
    (expireSubscriptions c)
    (close c) 

add ::
  Connection ->
  Topic ->
  Callback ->
  Subscription ->
  SubscriptionDbApiResult ()
add c t cb s = syncIO . execute c q $ SubscriptionRow  t cb s
  where
    q = " INSERT OR REPLACE INTO subscription \
        \ (topic,callback,started_at,expires_at,secret,from_user) \
        \ VALUES (?,?,?,?,?,?) "

remove :: Connection -> Topic -> Callback -> SubscriptionDbApiResult ()
remove c t cb = syncIO . execute c q $ (t,cb)
  where
    q = " DELETE FROM subscription WHERE topic = ? and callback = ? "

getTopicSubscriptions ::
  Connection ->
  Topic ->
  SubscriptionDbApiResult [(Callback,Subscription)]
getTopicSubscriptions c t = fmap toTuples . syncIO . query c q $ Only t
  where
    q = " SELECT topic, callback,started_at,expires_at,secret,from_user\
        \ FROM subscription WHERE topic = ? "    
    toTuples = fmap (\ (SubscriptionRow _ cb s) -> (cb,s) )

getAllSubscriptions ::
  Connection ->
  SubscriptionDbApiResult [(Topic,Callback,Subscription)]
getAllSubscriptions c  = fmap toTuples . syncIO . query_ c $ q 
  where
    q = " SELECT topic,callback,started_at,expires_at,secret,from_user \
        \ FROM subscription "
    toTuples = fmap (\ (SubscriptionRow t cb s) -> (t,cb,s))

expireSubscriptions :: Connection -> UTCTime -> SubscriptionDbApiResult ()
expireSubscriptions c now = syncIO . execute c q $ Only now
  where
    q = " DELETE FROM subscription WHERE expires_at < ? "

ddl :: Query
ddl =
  "CREATE TABLE subscription (\
  \   topic TEXT NOT NULL\
  \ , callback TEXT NOT NULL\
  \ , started_at DATETIME NOT NULL\
  \ , expires_at DATETIME NOT NULL\
  \ , secret TEXT \
  \ , from_user TEXT \
  \ , PRIMARY KEY (topic,callback) \
  \ )"
