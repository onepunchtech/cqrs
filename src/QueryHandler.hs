-- | 

module QueryHandler where

class (MonadIO m) => QueryHandler m where
  type State m :: *
  type Query m :: *
  type QueryRes m :: *
  type QueryId m :: *
  type ConnId m :: *

  query :: (State m) -> (Query m) -> m (QueryRes m)
  subscribe :: (State m) -> (Query m) -> (ConnId m) -> m (QueryId m, TMChan (QueryRes m))
  unsubscribe :: (State m) -> (ConnId m) -> (QueryId m) -> m ()
  disconnect :: (State m) -> (ConnId m) -> m ()

