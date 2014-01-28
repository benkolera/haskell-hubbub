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
  )

import Network.HTTP.Conduit (parseUrl,withManager,http,urlEncodedBody)

-----------------------------------------------------------------------------
-- AcidState DB -------------------------------------------------------------
-----------------------------------------------------------------------------

data Post = Post { subject::Text , body::Text } deriving (Typeable,Show,Eq)
$(deriveSafeCopy 0 'base ''Post)
data Db = Db { posts::[Post] } deriving (Typeable,Show,Eq)
$(deriveSafeCopy 0 'base ''Db)

getPosts :: Query Db [Post]
getPosts = posts <$> ask

addPost :: Post -> Update Db ()
addPost p = modify ( Db . (p:) . posts )

clearPosts :: Update Db ()
clearPosts = put ( Db [] )
  
$(makeAcidic ''Db ['getPosts,'addPost,'clearPosts])

-----------------------------------------------------------------------------
-- Scotty Application -------------------------------------------------------
-----------------------------------------------------------------------------

-- Generates a ToJson instance with Aeson template haskell.
$(deriveToJSON defaultOptions ''Post)
                                      
port :: Int
port = 5001

main :: IO ()
main = do
  -- Open the DB, initialising it to an empty list of posts if needed.
  acid <- openLocalState $ Db []
  
  scotty port $ do
    -- Log all requests to std out.
    middleware logStdoutDev
    -- This wont work if cabal installed. Can use data-dir instead.
    middleware $ staticPolicy (noDots >-> addBase "www/static")
    
    get "/" $ do
      ps <- liftIO $ query acid GetPosts
      blaze . postsHtml $ ps

    post "/" $ do
      sub <- TL.toStrict <$> param "subject" 
      bod <- TL.toStrict <$> param "body"
      _ <- liftIO $ update acid $ AddPost (Post sub bod)
      liftIO publish
      redirect "/"      

    get "/json" $ do
      ps <- liftIO $ query acid GetPosts

      -- json :: ToJson a => a -> ActionM (). Uses instance created above.
      json ps
      
    get "/clear" $ do
      _ <- liftIO $ update acid ClearPosts
      liftIO publish
      redirect "/"      

-----------------------------------------------------------------------------
-- Publish via Http Conduit -------------------------------------------------
-----------------------------------------------------------------------------

-- Buyer beware. This code throws exceptions. We'll tidy these up in Hubbub
-- but for now Scotty will catch them and give a 500 so that's OK enough here

publish :: IO ()
publish = do
  -- Will throw an exception if the url is not valid.
  request <- parseUrl "http://localhost:5000/publish"
  
  withManager $ \manager -> do
    -- Will throw an exception if status is not 2xx
    _ <- http (postRequest request) manager
    return ()

  where
    -- Add the post form parameters that the hub is expecting in the post.
    postRequest = urlEncodedBody [("hub.topic","http://localhost:5001/json")]

-----------------------------------------------------------------------------
-- Create web page with blaze    
-----------------------------------------------------------------------------

blaze :: H.Html -> ActionM ()
blaze = html . renderHtml

postsHtml :: [Post] -> H.Html
postsHtml ps = H.html $ do
  H.head $ 
    H.link H.! A.rel "stylesheet" H.! A.href "/css/main.css"    
  H.body $ 
    H.div H.! A.class_ "content" $ do
      H.h1 "Publisher"
      addPostHtml
      forM_ ps postHtml

addPostHtml :: H.Html
addPostHtml = H.div H.! A.class_ "post" $ 
  H.form H.! A.action "/" H.! A.method "POST" $ do
    H.input H.! A.name "subject" H.! A.type_ "input" H.! A.placeholder "Subject"
    H.textarea "" H.! A.name "body" H.! A.rows "5" H.! A.cols "23"
    H.input H.! A.type_ "submit" H.! A.value "Add Post"

postHtml :: Post -> H.Html    
postHtml (Post s b ) = H.div H.! A.class_ "post" $ do
  H.h2 $ H.toHtml s
  H.pre $ H.toHtml b

-----------------------------------------------------------------------------
