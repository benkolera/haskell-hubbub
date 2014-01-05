module Network.Hubbub.TestHelpers (topic,callback,url) where

import Network.Hubbub.SubscriptionDb
import Network.URL
import Data.Text

topic :: Text -> Topic
topic n    = Topic $ url "publish.com" ("/topic/" `append` n)

callback :: Text -> Callback
callback n = Callback $ url "subscribe.com" ("/callback/" `append` n)

url :: Text -> Text -> URL
url hostNm path = 
  URL (Absolute $ Host (HTTP False) (unpack hostNm) Nothing) (unpack path) []
