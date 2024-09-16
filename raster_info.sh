#!/bin/bash
src=$1
dst=$2

feature() {
  f_src=$1
  f_dst=$2
  # extract las info
  json=$(gdalinfo -stats -json "$f_src")
  # parse to csv
  csv=$(jq --raw-output '["location",
  "format",
  "srs",
  "srs_wkt",
  "horizontal_epsg", "vertical_epsg", "geoid",
  "horizontal_units", "vertical_units",
  "columns", "rows",
  "x_res", "y_res",
  "type", "blocK_x", "block_y",
  "z_min", "z_max", "no_data",
  "geometry", "info"] as $header |
  [.description,
  .driverLongName,
  .stac.["proj:projjson"].name,
  .coordinateSystem.wkt,
  (if .stac.["proj:projjson"].components[0].id ? then .stac.["proj:projjson"].components[0].id.code else "unknown" end),
  (if .stac.["proj:projjson"].components[1].id ? then .stac.["proj:projjson"].components[1].id.code else "unknown" end),
  (if .stac.["proj:projjson"].components[1].geoid_model ? then .stac.["proj:projjson"].components[1].geoid_model.name else "unknown" end),
  (if .stac.["proj:projjson"].components[0].coordinate_system.axis[0] ? then .stac.["proj:projjson"].components[0].coordinate_system.axis[0].unit else "unknown" end),
  (if .stac.["proj:projjson"].components[1].coordinate_system.axis[0] ? then .stac.["proj:projjson"].components[1].coordinate_system.axis[0].unit else "unknown" end),
  .size[0], .size[1],
  .geoTransform[1], .geoTransform[5],
  (.bands[0] | .type, .block[0], .block[1], .min, .max, .noDataValue),
  (.wgs84Extent | tostring), (. | tostring)] as $data |
  $header, $data | @csv' <<< "$json")
  # extract horizontal srs
  srs=$(jq --raw-output '(if .stac.["proj:projjson"].components[0].id ? then (.stac.["proj:projjson"].components[0].id | .authority+":"+(.code | tostring)) else .coordinateSystem.wkt end)' <<< "$json")
  # convert csv to feature
  if [[ -z $f_dst ]]; then
    ogr2ogr -oo GEOM_POSSIBLE_NAMES=geometry -oo KEEP_GEOM_COLUMNS=NO -s_srs wgs84 -t_srs "$srs" -f GeoJSON /vsistdout/ CSV:/vsistdin/ <<< "$csv"
  else
    ogr2ogr -oo GEOM_POSSIBLE_NAMES=geometry -oo KEEP_GEOM_COLUMNS=NO -s_srs wgs84 -t_srs "$srs" "$f_dst" CSV:/vsistdin/ <<< "$csv"
  fi
}

directory() {
  d_src=$1
  d_dst=$2
  # find raster files and create features
  find "$d_src" -type f -regextype posix-egrep -regex ".*\.(tif|img)$" | while read -r f
  do
    name=$(basename -- "$f")
    tmp="/tmp/${name%.*}.geojson"
    feature "$f" "$tmp"
    if [[ -f $d_dst ]]; then
      ogr2ogr -append "$d_dst" "$tmp"
    else
      ogr2ogr "$d_dst" "$tmp"
    fi
    rm "$tmp"
  done
}
# Remove existing output dataset
if [[ -f $dst ]]; then
  rm "$dst"
fi

if [[ -d $src ]]; then
    directory "$src" "$dst"
elif [[ -f $src ]]; then
    feature "$src" "$dst"
else
    echo "$src is not valid"
    exit 1
fi