import time

class Deduplicator:
    def __init__(self, hours=24):
        self.ttl = hours * 3600
        self.seen = {}

    def is_new(self, key):
        now = time.time()
        self.seen = {k:v for k,v in self.seen.items() if now-v < self.ttl}
        return key not in self.seen

    def mark(self, key):
        self.seen[key] = time.time()
