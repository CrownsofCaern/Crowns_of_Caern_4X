"""Compatibility entry point; ultimate exports now use the main asset pipeline."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'tools/assets'))
from crowns_of_cinder_assets.ultimate_buildings import stage


def export():
    stage(ROOT)


if __name__ == '__main__':
    export()
