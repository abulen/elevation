import os
from tempfile import NamedTemporaryFile
from osgeo import gdal


def build_vrt_string(input_files, options: str = '-r cubic'):
    sources = list()
    for f in input_files:
        if f.startswith('http'):
            sources.append(f'/vsicurl/{f}')
        else:
            sources.append(f)
    with NamedTemporaryFile(delete=True, suffix='.vrt') as temp:
        options = gdal.BuildVRTOptions(options)
        vrt = gdal.BuildVRT(temp.name, sources, options=options)
        vrt = None
        xml = temp.read()
    return xml
