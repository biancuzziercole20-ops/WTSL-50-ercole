from abc import ABC, abstractmethod
from typing import Iterable
from ..models import Listing

class Connector(ABC):
    platform = "Unknown"

    @abstractmethod
    def search(self, query: str) -> Iterable[Listing]:
        raise NotImplementedError
