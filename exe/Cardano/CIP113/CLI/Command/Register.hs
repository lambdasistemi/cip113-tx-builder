module Cardano.CIP113.CLI.Command.Register (
    Options (..),
    parser,
    run,
) where

import Options.Applicative (Parser)
import System.Exit (ExitCode (ExitFailure), exitWith)
import System.IO (hPutStrLn, stderr)

data Options = Options
    deriving (Show, Eq)

parser :: Parser Options
parser = pure Options

run :: Bool -> Options -> IO ()
run jsonOutput Options = do
    if jsonOutput
        then putStrLn "{\"error\":\"register not yet implemented\"}"
        else hPutStrLn stderr "register: not yet implemented"
    exitWith (ExitFailure 2)
