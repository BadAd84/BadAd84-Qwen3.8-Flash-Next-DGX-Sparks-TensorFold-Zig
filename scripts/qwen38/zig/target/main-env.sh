# Settings upstream main reads from the production launcher's environment (measured against main 1ece6e6db).
# The other 45 exported names belong to the production-branch engine and main ignores them; arms that run main's
# engine export only these seven so a name main does not read cannot be mistaken for a lever under test.
export TENSORFOLD_MEMORY_RESERVE_GIB=10
export TENSORFOLD_NO_UPDATE_CHECK=1
export TENSORFOLD_VIDEO_TOKENS=16384
export TF_FLASHNEXT_BATCH_DRAWS=1
export TF_FLASHNEXT_CONFIDENCE=-0.15
export TF_FLASHNEXT_DEPTH=15
export TF_FLASHNEXT_WINDOW=64
