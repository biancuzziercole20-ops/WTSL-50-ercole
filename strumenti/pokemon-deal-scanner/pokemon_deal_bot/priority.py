from dataclasses import dataclass
from time import time

@dataclass
class Notification:
    priority: int
    timestamp: float

class RateLimiter:
    def __init__(self, normal_max=5, window_seconds=600):
        self.normal_max = normal_max
        self.window_seconds = window_seconds
        self.sent = []

    def allow(self, priority: int) -> bool:
        now = time()
        self.sent = [x for x in self.sent if now - x.timestamp < self.window_seconds]
        if priority == 1:
            return True
        return sum(1 for x in self.sent if x.priority != 1) < self.normal_max

    def record(self, priority: int):
        self.sent.append(Notification(priority, time()))
