from pydantic import BaseModel


class OutwardRequest(BaseModel):
    outward_postcode: str

    @classmethod
    def from_full_postcode(cls, full_postcode: str) -> "OutwardRequest":
        return cls(outward_postcode=full_postcode.split(" ")[0])
