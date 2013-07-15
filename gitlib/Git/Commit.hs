module Git.Commit where

import           Control.Monad
import           Control.Monad.Trans.Class
import           Data.Conduit
import qualified Data.Conduit.List as CL
import           Data.Function
import           Data.HashSet (HashSet)
import qualified Data.HashSet as HashSet
import           Data.List
import           Data.Maybe
import           Data.Tagged
import           Data.Text (Text)
import           Git.Tree
import           Git.Types
import           Prelude hiding (FilePath)

commitTreeEntry :: Repository m
                => Commit m
                -> Text
                -> m (Maybe (TreeEntry m))
commitTreeEntry c path = flip treeEntry path =<< lookupTree (commitTree c)

copyCommitOid :: (Repository m, Repository n) => CommitOid m -> n (CommitOid n)
copyCommitOid = parseObjOid . renderObjOid

copyCommit :: (Repository m, Repository (t m), MonadTrans t)
           => CommitOid m
           -> Maybe Text
           -> HashSet Text
           -> t m (CommitOid (t m), HashSet Text)
copyCommit cr mref needed = do
    let oid = untag cr
        sha = renderOid oid
    commit <- lift $ lookupCommit cr
    oid2   <- parseOid sha
    if HashSet.member sha needed
        then do
        let parents = commitParents commit
        (parentRefs,needed') <- foldM copyParent ([],needed) parents
        (tr,needed'') <- copyTree (commitTree commit) needed'

        commit' <- createCommit (reverse parentRefs) tr
            (commitAuthor commit)
            (commitCommitter commit)
            (commitLog commit)
            mref

        let coid = commitOid commit'
            x    = HashSet.delete sha needed''
        return $ coid `seq` x `seq` (coid, x)

        else return (Tagged oid2, needed)
  where
    copyParent (prefs,needed') cref = do
        (cref2,needed'') <- copyCommit cref Nothing needed'
        let x = cref2 `seq` (cref2:prefs)
        return $ x `seq` needed'' `seq` (x,needed'')

listCommits :: Repository m
            => Maybe (CommitOid m) -- ^ A commit we may already have
            -> CommitOid m         -- ^ The commit we need
            -> m [CommitOid m]     -- ^ All the objects in between
listCommits mhave need =
    sourceObjects mhave need False
        $= CL.mapM (\(CommitObjOid c) -> return c)
        $$ CL.consume

traverseCommits :: Repository m => (CommitOid m -> m a) -> CommitOid m -> m [a]
traverseCommits f need = mapM f =<< listCommits Nothing need

traverseCommits_ :: Repository m => (CommitOid m -> m ()) -> CommitOid m -> m ()
traverseCommits_ = (void .) . traverseCommits
