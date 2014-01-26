{-# LANGUAGE DeriveDataTypeable, TypeFamilies, TemplateHaskell #-}
module Main where

import Prelude (Int)

import Control.Applicative ((<$>))
import Control.Monad (forM_,return)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader(ask)
import Control.Monad.State(modify,put)
import Data.Acid (Query,Update,update,query,makeAcidic,openLocalState)
import Data.Aeson.TH (deriveToJSON,defaultOptions)
import Data.Eq (Eq)
import Data.Function (($),(.))
import Data.SafeCopy (deriveSafeCopy,base)
import Data.Text (Text)
import qualified Data.Text.Lazy as TL
import Data.Typeable (Typeable)
import Network.Wai.Middleware.Static
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import System.IO (IO)
import Text.Show (Show)
import Text.Blaze.Html.Renderer.Text (renderHtml)
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A
import Web.Scotty
  ( ActionM
  , html
  , scotty
  , get
  , json
  , post
  , middleware
  , param
  , redirect
  , file )

import Network.HTTP.Conduit (parseUrl,withManager,http,urlEncodedBody)

data Post = Post { subject::Text , body::Text } deriving (Typeable,Show,Eq)
$(deriveSafeCopy 0 'base ''Post)
data Db = Db { posts::[Post] } deriving (Typeable,Show,Eq)
$(deriveSafeCopy 0 'base ''Db)

$(deriveToJSON defaultOptions ''Post)
  
getPosts :: Query Db [Post]
getPosts = posts <$> ask

addPost :: Post -> Update Db ()
addPost p = modify ( Db . (p:) . posts )

clearPosts :: Update Db ()
clearPosts = put ( Db [] )
  
$(makeAcidic ''Db ['getPosts,'addPost,'clearPosts])
  
port :: Int
port = 5001

main :: IO ()
main = do
  acid <- openLocalState $ Db []
  scotty port $ do
    middleware logStdoutDev
    middleware $ staticPolicy (noDots >-> addBase "www/static")
    get "/" $ do
      ps <- liftIO $ query acid GetPosts
      blaze . postsHtml $ ps

    get "/json" $ do
      ps <- liftIO $ query acid GetPosts
      json ps
      
    get "/edit" $ file "www/publisher/edit.html"

    post "/clear" $ do
      _ <- liftIO $ update acid ClearPosts
      liftIO publish
      
    post "/edit" $ do
      sub <- TL.toStrict <$> param "subject" 
      bod <- TL.toStrict <$> param "body"
      _ <- liftIO $ update acid $ AddPost (Post sub bod)
      liftIO publish
      redirect "/"

publish :: IO ()
publish = do
  request <- parseUrl "http://localhost:5000/publish" 
  withManager $ \manager -> do
    _ <- http (postRequest request) manager
    return ()

  where
    postRequest = urlEncodedBody [("hub.topic","http://localhost:5001/json")]

blaze :: H.Html -> ActionM ()
blaze = html . renderHtml

postsHtml :: [Post] -> H.Html
postsHtml ps = H.html $ do
  H.head $ 
    H.link H.! A.rel "stylesheet" H.! A.href "/css/main.css"    
  H.body $ 
    H.div H.! A.class_ "content" $ do
      H.h1 "Posts"
      H.a H.! A.href "/edit" $ "Add post"
      forM_ ps postHtml

postHtml :: Post -> H.Html    
postHtml (Post s b ) = H.div H.! A.class_ "post" $ do
  H.h2 $ H.toHtml s
  H.pre $ H.toHtml b
