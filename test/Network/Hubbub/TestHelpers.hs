module Network.Hubbub.TestHelpers (topic,callback,resource) where

import Network.Hubbub.SubscriptionDb 
  ( HttpResource(HttpResource)
  , Topic(Topic)
  , Callback(Callback))
import Prelude (($),Bool(False),Maybe(Nothing),undefined)
import Data.Text (append,Text)

topic :: Text -> Topic
topic n    = Topic $ resource "publish.com" ("/topic/" `append` n)

callback :: Text -> Callback
callback n = Callback $ resource "subscribe.com" ("/callback/" `append` n)

resource :: Text -> Text -> HttpResource
resource host path = HttpResource False host 80 path []
