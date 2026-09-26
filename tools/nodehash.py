import RNS
import os, sys
# Node destination hash = hash of the NomadNet identity under the
# "nomadnetwork.node" aspect. Stable for the life of the identity file.
idf = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "/root/.nomadnetwork/storage/identity")
identity = RNS.Identity.from_file(idf)
h = RNS.Destination.hash_from_name_and_identity("nomadnetwork.node", identity)
print("NODE:", RNS.hexrep(h, delimit=False))
