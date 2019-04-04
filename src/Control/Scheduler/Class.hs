{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE UndecidableInstances   #-}

module Control.Scheduler.Class (
  MonadScheduler(..),
  MonadJobs(..)
) where

import           Control.Scheduler.Chronometer (MonadChronometer (..))
import           Control.Scheduler.Task.Class  (Job (..), Task (..))
import           Control.Scheduler.Time        (ScheduledTime (..))

class (MonadChronometer m, MonadJobs d m) => MonadScheduler d m | m -> d where
  schedule :: (Task t, TaskData t ~ d) => t -> m ()
  react    :: (d -> m ()) -> m ()

class MonadJobs d m | m -> d where
  pushQueue :: ScheduledTime -> Job d -> m ()
  popQueue  :: m (Maybe (ScheduledTime, Job d))
  execute   :: m () -> m ()
  enumerate :: m [(ScheduledTime, Job d)]

whenJust :: Applicative f => Maybe a -> (a -> f ()) -> f ()
whenJust Nothing  _      = pure ()
whenJust (Just x) action = action x

instance (Monad m, MonadChronometer m, MonadJobs d m) => MonadScheduler d m where
  schedule task = do
    mbExecutesAt <- runAt task <$> now

    whenJust mbExecutesAt $ \executesAt ->
      pushQueue executesAt (Job task)

  react handler = do
    mbItem <- popQueue

    whenJust mbItem $ \(runTime, job) -> do
        sleepUntil runTime

        execute (apply job handler)

        mbNextJob <- nextJob job <$> now

        whenJust mbNextJob schedule

        react handler
