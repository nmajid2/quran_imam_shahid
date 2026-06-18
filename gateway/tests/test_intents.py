"""The security boundary: only allow-listed, in-range intents validate."""

import pytest
from pydantic import TypeAdapter, ValidationError

from qis.schema.intents import Intent, ayah_in_bounds

adapter = TypeAdapter(Intent)


def test_valid_open_ayah():
    intent = adapter.validate_python({"action": "open_ayah", "surah": 2, "ayah": 255})
    assert intent.surah == 2 and intent.ayah == 255


def test_play_recitation_aliases_from_to():
    intent = adapter.validate_python(
        {"action": "play_recitation", "surah": 36, "from": 1, "to": 5}
    )
    assert intent.from_ayah == 1 and intent.to_ayah == 5


def test_unknown_action_rejected():
    # An arbitrary "command" is NOT in the allow-list -> rejected.
    with pytest.raises(ValidationError):
        adapter.validate_python({"action": "run_shell", "cmd": "rm -rf /"})


def test_surah_out_of_range_rejected():
    with pytest.raises(ValidationError):
        adapter.validate_python({"action": "open_ayah", "surah": 200, "ayah": 1})


def test_answer_requires_confidence_enum():
    with pytest.raises(ValidationError):
        adapter.validate_python(
            {"action": "answer", "text": "x", "confidence": "very-sure"}
        )


def test_ayah_in_bounds_helper():
    assert ayah_in_bounds(1, 7) is True
    assert ayah_in_bounds(1, 8) is False
    assert ayah_in_bounds(112, 4) is True
    assert ayah_in_bounds(112, 5) is False
