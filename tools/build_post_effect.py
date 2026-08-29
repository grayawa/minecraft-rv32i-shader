"""Generate MCRV post-effect graphs for demo, probe, and Linux profiles."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


RAM_WIDTH = 4096
RAM_HEIGHT = 768
GUEST_WIDTH = 2048
GUEST_HEIGHT = 1024
MTD_WIDTH = 4096
MTD_HEIGHT = 3447


@dataclass(frozen=True)
class Profile:
    name: str
    guest: str
    dtb: str
    mtd: str
    steps_per_half: int


PROFILES = (
    Profile("rv32i", "guest_demo", "dtb_mcrv", "mtd_empty", 1),
    Profile("rv32i_boot", "guest_boot_probe", "dtb_mcrv", "mtd_empty", 1),
    Profile("rv32i_linux", "guest_linux", "dtb_rvc_linux", "mtd_linux", 32),
    Profile("rv32i_linux_fast", "guest_linux", "dtb_rvc_linux", "mtd_linux", 64),
    Profile("rv32i_linux_turbo", "guest_linux", "dtb_rvc_linux", "mtd_linux", 128),
    Profile("rv32i_linux_ultra", "guest_linux", "dtb_rvc_linux", "mtd_linux", 256),
)


def target(width: int, height: int, persistent: bool = True) -> dict[str, object]:
    return {
        "width": width,
        "height": height,
        "persistent": persistent,
        "clear_color": [0.0, 0.0, 0.0, 0.0],
    }


def image_input(name: str, location: str, width: int, height: int) -> dict[str, object]:
    return {
        "sampler_name": name,
        "location": f"mcrv:{location}",
        "width": width,
        "height": height,
    }


def step_pass(state_input: str, state_output: str, ram: str,
              profile: Profile) -> dict[str, object]:
    return {
        "vertex_shader": "minecraft:core/screenquad",
        "fragment_shader": "mcrv:post/rv32_step",
        "inputs": [
            {"sampler_name": "State", "target": state_input},
            {"sampler_name": "Ram", "target": ram},
            image_input("GuestImage", profile.guest, GUEST_WIDTH, GUEST_HEIGHT),
            image_input("DtbImage", profile.dtb, 1024, 1),
            image_input("MtdImage", profile.mtd, MTD_WIDTH, MTD_HEIGHT),
            {"sampler_name": "Input", "target": "input"},
        ],
        "output": state_output,
    }


def commit_pass(ram_input: str, ram_output: str, state: str,
                profile: Profile) -> dict[str, object]:
    return {
        "vertex_shader": "minecraft:core/screenquad",
        "fragment_shader": "mcrv:post/rv32_ram_commit",
        "inputs": [
            {"sampler_name": "Ram", "target": ram_input},
            {"sampler_name": "State", "target": state},
            image_input("GuestImage", profile.guest, GUEST_WIDTH, GUEST_HEIGHT),
            image_input("MtdImage", profile.mtd, MTD_WIDTH, MTD_HEIGHT),
        ],
        "output": ram_output,
    }


def clear_pass(state_input: str, state_output: str) -> dict[str, object]:
    return {
        "vertex_shader": "minecraft:core/screenquad",
        "fragment_shader": "mcrv:post/rv32_cache_clear",
        "inputs": [{"sampler_name": "State", "target": state_input}],
        "output": state_output,
    }


def build_profile(profile: Profile) -> dict[str, object]:
    passes: list[dict[str, object]] = [
        {
            "vertex_shader": "minecraft:core/screenquad",
            "fragment_shader": "minecraft:post/blit",
            "inputs": [{"sampler_name": "In", "target": "minecraft:main"}],
            "uniforms": {
                "BlitConfig": [
                    {
                        "name": "ColorModulate",
                        "type": "vec4",
                        "value": [1.0, 1.0, 1.0, 1.0],
                    }
                ]
            },
            "output": "scene",
        },
        {
            "vertex_shader": "minecraft:core/screenquad",
            "fragment_shader": "mcrv:post/rv32_input_capture",
            "inputs": [{"sampler_name": "Scene", "target": "scene"}],
            "output": "input",
        },
    ]

    current_state = "state_a"
    current_ram = "ram_a"
    for _half in range(2):
        for _step in range(profile.steps_per_half):
            next_state = "state_b" if current_state == "state_a" else "state_a"
            passes.append(step_pass(current_state, next_state, current_ram, profile))
            current_state = next_state
        next_ram = "ram_b" if current_ram == "ram_a" else "ram_a"
        passes.append(commit_pass(current_ram, next_ram, current_state, profile))
        current_ram = next_ram
        next_state = "state_b" if current_state == "state_a" else "state_a"
        passes.append(clear_pass(current_state, next_state))
        current_state = next_state

    if current_state != "state_a" or current_ram != "ram_a":
        raise AssertionError("two-half graph must finish on state_a and ram_a")

    passes.append(
        {
            "vertex_shader": "minecraft:core/screenquad",
            "fragment_shader": "mcrv:post/rv32_display",
            "inputs": [
                {"sampler_name": "Scene", "target": "scene"},
                {"sampler_name": "State", "target": current_state},
                {"sampler_name": "Ram", "target": current_ram},
            ],
            "output": "minecraft:main",
        }
    )
    return {
        "targets": {
            "scene": {},
            "input": target(1, 1, persistent=False),
            "state_a": target(128, 128),
            "state_b": target(128, 128),
            "ram_a": target(RAM_WIDTH, RAM_HEIGHT),
            "ram_b": target(RAM_WIDTH, RAM_HEIGHT),
        },
        "passes": passes,
    }


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    output_directory = project / "assets" / "mcrv" / "post_effect"
    for profile in PROFILES:
        output = output_directory / f"{profile.name}.json"
        output.write_text(
            json.dumps(build_profile(profile), indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        print(f"{output.name}: {profile.steps_per_half * 2} instructions/frame")


if __name__ == "__main__":
    main()
