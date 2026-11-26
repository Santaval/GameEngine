<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.10.2" name="terrain" tilewidth="16" tileheight="16" tilecount="8" columns="4">
 <image source="gfx/tiles.png" width="64" height="32"/>
 <tile id="1">
  <animation>
   <frame tileid="1" duration="100"/>
   <frame tileid="2" duration="200"/>
  </animation>
 </tile>
 <tile id="3" type="water">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
</tileset>
