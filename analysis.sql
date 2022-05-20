-- Flood Hazard Analysis in Fort Bend County, Texas

-- PARCELS - DATA PROCESSING
	CREATE INDEX parcel_centroids_geom_idx
		ON
			studyarea_parceldata
		USING	
			GIST (ST_Centroid(ST_Transform(geom, 4326)));

	CREATE INDEX studyarea_hazard_geom_idx
		ON 
			studyarea_hazard
		USING 
			GIST (ST_Transform(geom, 4326));

-- PARCELS - DATA ANALYSIS
	WITH parcel_centroids as (
		SELECT 
			ST_Centroid(ST_Transform(geom, 4326)) as geom, totalvalue
		FROM 
			studyarea_parceldata
		WHERE
			totalvalue IS NOT NULL
	)
	SELECT
		h.fld_zone, h.zone_subty, AVG(c.totalvalue), stddev_samp(c.totalvalue), COUNT(c.totalvalue)
	FROM
		parcel_centroids c
	INNER JOIN
		studyarea_hazard h
	ON
		ST_Intersects(c.geom, ST_Transform(h.geom, 4326))
	GROUP BY
		h.fld_zone, h.zone_subty;

-- DEMOGRAPHICS - DATA PROCESSING
	CREATE TABLE studyarea_blocks as (
		SELECT
			sctbkey, shape_area, ST_Transform(geom, 4326)
		FROM
			texas_blocks
		WHERE
			cnty = '157'
	);

	CREATE TABLE studyarea_hazard_validgeom as (
		SELECT
			fld_zone, zone_subty, ST_UNION(ST_Buffer(ST_Transform(geom, 4326), 0)) as geom
		FROM
			studyarea_hazard
		GROUP BY
			fld_zone, zone_subty
	);

	CREATE INDEX studyarea_hazard_validgeom_geom_idx
		ON
			studyarea_hazard_validgeom
		USING
			GIST (geom);

	CREATE INDEX studyarea_blocks_geom_idx
		ON
			studyarea_blocks
		USING
			GIST (geom);

-- DEMOGRAPHICS - DATA ANALYSIS
	
	-- CREATING A TABLE W/ PERCENTAGES OF COVER FOR EVERY HAZARD TYPE AND EVERY BLOCK
	CREATE TABLE hazard_percentage_blocks as (
		SELECT
			block.sctbkey, haz.fld_zone as zone, haz.zone_subty as subtype, ST_Area(ST_Intersection(block.geom, haz.geom)) / ST_Area(block.geom) as pcover
		FROM(
	        	SELECT sctbkey, ST_Transform(geom, 4326) as geom
	       		FROM studyarea_fbc_blocks
			) as block, 
			(
	        	SELECT fld_zone, zone_subty, ST_Transform(geom, 4326) as geom
	        	FROM studyarea_hazard_validgeom
	    	) as haz
		WHERE
			ST_Intersects(block.geom, haz.geom)
	);

	-- CREATING VIEW WITH THE HAZARD THAT COVERS THE LARGEST AREA OF THE BLOCK
	CREATE VIEW max_block_pcover as (
		WITH max_coverages as (
			SELECT
				sctbkey, MAX(pcover) as coverage
			FROM
				hazard_percentage_blocks
			GROUP BY
				sctbkey
		)
		SELECT
			mc.sctbkey, mc.coverage, hp.zone, hp.subtype,
			CASE
				WHEN zone = 'A' AND subtype IS NULL THEN 1
				WHEN zone = 'X' AND subtype = 'AREA OF MINIMAL FLOOD HAZARD' THEN 2
				WHEN zone = 'X' AND subtype = 'AREA WITH REDUCED FLOOD RISK DUE TO LEVEE' THEN 3
				WHEN zone = 'AE' AND subtype IS NULL THEN 4
				WHEN zone = 'AO' AND subtype IS NULL THEN 5
				WHEN zone = 'AE' AND subtype = 'FLOODWAY' THEN 6
				WHEN zone = 'X' AND subtype = '0.2 PCT ANNUAL CHANCE FLOOD HAZARD' THEN 7
			END AS category
		FROM
			max_coverages mc
		INNER JOIN
			hazard_percentage_blocks hp
		ON
			mc.sctbkey = hp.sctbkey AND mc.coverage = hp.pcover
	);

	-- CALCULATING DEMOGRAPHIC INFO AND JOINING TO MAX HAZARD COVERAGE VALUES
	WITH joined_demo_data as (
		SELECT
			pc.sctbkey, pc.category, (d.anglo::float / d.total::float) as anglo_pct, (d.asian::float/ d.total::float) as asian_pct,
			(d.hisp::float / d.total::float) as hisp_pct, (d.black::float / d.total::float) as black_pct
		FROM
			max_block_pcover pc
		INNER JOIN
			studyarea_blocks_demo d
		ON 
			pc.sctbkey = d.sctbkey
		WHERE 
			d.total <> 0
	)
	SELECT
		category, AVG(anglo_pct) as anglo_avg, stddev_samp(anglo_pct) as anglo_sd, AVG(asian_pct) as asian_avg, stddev_samp(asian_pct) as asian_sd,
		AVG(hisp_pct) as hisp_avg, stddev_samp(hisp_pct) as hisp_sd, AVG(black_pct) as black_avg, stddev_samp(black_pct) as black_sd, COUNT(*)
	FROM
		joined_demo_data
	GROUP BY
		category;




