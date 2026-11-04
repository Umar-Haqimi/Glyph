# VECTORS (pointer)

The commands, tool versions and engine settings used to generate the golden vectors (SPEC 7.1) are in
[`docs/m0/VECTORS.md`](m0/VECTORS.md). That file keeps its M0 location because source comments, tests
and vector manifests link to it; this stub exists so the path named in SPEC section 9 resolves.

Things a release needs from it: re-recording the Stockfish 19 UCI transcripts (section 3) and capturing real
SSE streams (section 4); see [`docs/RELEASE.md`](RELEASE.md).
