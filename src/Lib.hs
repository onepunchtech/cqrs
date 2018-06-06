module Lib
    (
    ) where

import           Control.Concurrent.STM
import           Control.Exception              (finally)
import           Control.Monad                  (forever)
import qualified Data.ByteString.Lazy           as BS
import qualified Network.Wai
import qualified Network.Wai.Handler.WebSockets as WaiWS
import qualified Network.WebSockets             as WS

wsApp :: WS.ServerApp
wsApp pending = do
  conn <- WS.acceptRequest pending
  WS.forkPingThread conn 30
  finally (connect conn) disconnect
  where
    connect = undefined
    disconnect = undefined

type QueryId = String

data CQRSOps = JoinQuery BS.ByteString
             | LeaveQuery QueryId
             | Write BS.ByteString

connect conn = forever $ do
  msg <- WS.receiveData conn
  putStrLn $ show (msg :: BS.ByteString)
  -- connect to query
  -- leave query
  -- handle write

data QuerySubscriptionState

joinQuery :: BS.ByteString -> QuerySubscriptionState -> STM QueryId
joinQuery = undefined

leaveQuery :: QueryId -> QuerySubscriptionState -> STM ()
leaveQuery = undefined

