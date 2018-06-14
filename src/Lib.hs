{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies      #-}

module Lib
    (
    ) where

import           Control.Concurrent
import           Control.Concurrent.STM
import           Control.Concurrent.STM.TMChan
import           Control.Exception              (finally)
import           Control.Monad                  (forever, void)
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Data.Aeson
import qualified Data.ByteString.Lazy           as BS
import qualified Data.Map                       as M
import           Data.Maybe
import qualified Data.Text                      as T
import           Data.UUID
import           Data.UUID.V4
import           GHC.Generics
import qualified Network.Wai
import qualified Network.Wai.Handler.WebSockets as WaiWS
import qualified Network.WebSockets             as WS

data QueryOp q = Query T.Text q
                   | Subscribe q
                   | Unsubscribe T.Text
                   deriving (Generic)

data QueryOpRes qr = QueryRes T.Text qr
                   | Subscribed T.Text
                   | Unsubscribed
                   deriving (Generic)

instance FromJSON (QueryOp T.Text)
instance ToJSON (QueryOpRes T.Text)

wsApp :: State IO -> WS.ServerApp
wsApp st pending = do
  conn <- WS.acceptRequest pending
  WS.forkPingThread conn 30
  connId <- toText <$> nextRandom
  finally (connect conn st connId) (disconnect st connId)

  where
    connect conn st connId = forever $ do
      msg <- WS.receiveData conn
      let (Just op) = decode msg :: Maybe (QueryOp (Query IO))
      res <- case op of
              Query correlationId q -> QueryRes correlationId <$> query st q
              Subscribe q -> do
                (qId, chan) <- subscribe st q connId
                forkIO $ forward conn qId chan
                return $ Subscribed qId
              Unsubscribe qId -> unsubscribe st connId qId >> return Unsubscribed
      WS.sendTextData conn (encode res)


    forward conn qId chan = do
      output <- atomically $ readTMChan chan
      case output of
        Just res -> do
          WS.sendTextData conn (encode (QueryRes qId res))
          forward conn qId chan
        Nothing -> return ()


instance QueryHandler IO where
  type State IO = TVar (M.Map T.Text (M.Map T.Text (TMChan T.Text)))
  type Query IO = T.Text
  type QueryRes IO = T.Text
  type QueryId IO = T.Text
  type ConnId IO = T.Text
  query st q = return "foo"

  subscribe st q connId = do
    chan <- newTMChanIO
    qId <- toText <$> nextRandom
    atomically $ modifyTVar st (M.alter (Just . maybe M.empty (M.insert qId chan)) connId)
    return (qId, chan)

  unsubscribe st connId qId = atomically $ do
    subs <- readTVar st
    updatedSubs <- case M.lookup connId subs of
                    Just subs -> do
                      case M.lookup qId subs of
                        Just chan -> closeTMChan chan
                        Nothing   -> return ()
                      return $ M.delete qId subs
                    Nothing   -> return M.empty

    writeTVar st (M.insert connId updatedSubs subs)

  disconnect st connId = atomically $ do
    subs <- readTVar st
    case M.lookup connId subs of
      Just chans -> forM_ chans closeTMChan
      Nothing    -> return ()
    writeTVar st (M.delete connId subs)
