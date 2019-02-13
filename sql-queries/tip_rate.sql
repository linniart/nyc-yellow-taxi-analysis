/* BigQuery Standard SQL
output dataset name = tip_rate.csv*/

WITH t2 AS
(
SELECT 
    t.*,
    tz_pu.zone_id as pickup_zone_id,
    tz_pu.zone_name as pickup_zone_name,
    tz_pu.borough as pickup_borough,
    tz_do.zone_id as dropoff_zone_id,
    tz_do.zone_name as dropoff_zone_name,
    tz_do.borough as dropoff_borough,
    CONCAT(tz_pu.borough,"-",tz_do.borough) as route_borough,
    CONCAT(tz_pu.zone_name,"-",tz_do.zone_name) as route_zone_name
FROM
(
SELECT *,
    TIMESTAMP_DIFF(dropoff_datetime,pickup_datetime,SECOND) as time_duration_in_secs,
    ROUND(trip_distance/TIMESTAMP_DIFF(dropoff_datetime,pickup_datetime,SECOND),2)*3600 as driving_speed_miles_per_hour,
    (CASE WHEN total_amount=0 THEN 0
    ELSE ROUND(tip_amount*100/total_amount,2) END) as tip_rate,
    EXTRACT(YEAR from pickup_datetime) as pickup_year,
    EXTRACT(MONTH from pickup_datetime) as pickup_month,
    CONCAT(CAST(EXTRACT(YEAR from pickup_datetime) as STRING),"-",CAST(EXTRACT(MONTH from pickup_datetime) AS STRING)) as pickup_yearmonth,
    EXTRACT(DATE from pickup_datetime) as pickup_date,
    FORMAT_DATE('%A',DATE(pickup_datetime)) as pickup_weekday_name,
    EXTRACT(HOUR from pickup_datetime) as pickup_hour,
    EXTRACT(YEAR from dropoff_datetime) as dropoff_year,
    EXTRACT(MONTH from dropoff_datetime) as dropoff_month,
    CONCAT(CAST(EXTRACT(YEAR from dropoff_datetime) as STRING),"-",CAST(EXTRACT(MONTH from dropoff_datetime) AS STRING)) as dropoff_yearmonth,
    EXTRACT(DATE from dropoff_datetime) as dropoff_date,
    FORMAT_DATE('%A',DATE(dropoff_datetime)) as dropoff_weekday_name,
    EXTRACT(HOUR from dropoff_datetime) as dropoff_hour
    
FROM `bigquery-public-data.new_york.tlc_yellow_trips_2016`
/* filter by latitude & longitude that are within the correct range */
WHERE 
  ((pickup_latitude BETWEEN -90 AND 90) AND
  (pickup_longitude BETWEEN -180 AND 180)) 
AND
  ((dropoff_latitude BETWEEN -90 AND 90) AND
  (dropoff_longitude BETWEEN -180 AND 180))
) t
/* find the boroughs and zone names for dropoff locations */
INNER JOIN `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom` tz_do ON 
(ST_DWithin(tz_do.zone_geom,ST_GeogPoint(dropoff_longitude, dropoff_latitude), 0))
/* find the boroughs and zone names for pickup locations */
INNER JOIN `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom` tz_pu ON 
(ST_DWithin(tz_pu.zone_geom,ST_GeogPoint(pickup_longitude, pickup_latitude), 0))
WHERE 
    pickup_datetime BETWEEN '2016-01-01' AND '2016-12-31' 
    AND dropoff_datetime BETWEEN '2016-01-01' AND '2016-12-31'
    AND TIMESTAMP_DIFF(dropoff_datetime,pickup_datetime,SECOND) > 0
    AND passenger_count > 0
    AND trip_distance >= 0 
    AND tip_amount >= 0 
    AND tolls_amount >= 0 
    AND mta_tax >= 0 
    AND fare_amount >= 0
    AND total_amount >= 0
)

,t3 AS
(SELECT 
pickup_borough,
(CASE 
    WHEN tip_rate = 0 THEN 'no tip'
    WHEN tip_rate <= 5 THEN 'Less than 5%'
    WHEN tip_rate <= 10 THEN '5% to 10%'
    WHEN tip_rate <= 15 THEN '10% to 15%'
    WHEN tip_rate <= 20 THEN '15% to 20%'
    WHEN tip_rate <= 25 THEN '20% to 25%'
    ELSE 'More than 25%' END)as tip_category,
COUNT(*) as no_of_trips
FROM t2
GROUP BY 1,2
ORDER BY pickup_borough ASC)

SELECT pickup_borough
     , tip_category
     , Sum(no_of_trips) as no_of_trips,
     (CASE 
          WHEN pickup_borough is null THEN (select sum(no_of_trips)
          FROM t3)
          
          WHEN pickup_borough is not null and tip_category is null THEN (select sum(no_of_trips)
          FROM t3)
          
          WHEN pickup_borough is not null and tip_category is not null THEN (select sum(no_of_trips)
          FROM t3
          WHERE pickup_borough = m.pickup_borough)
          END) as parent_sum,
       ROUND(Sum(no_of_trips)/(CASE 
          WHEN pickup_borough is null THEN (select sum(no_of_trips)
          FROM t3)
          
          WHEN pickup_borough is not null and tip_category is null THEN (select sum(no_of_trips)
          FROM t3)
          
          WHEN pickup_borough is not null and tip_category is not null THEN (select sum(no_of_trips)
          FROM t3
          WHERE pickup_borough = m.pickup_borough)
          END),2) as percentage
          
          
FROM t3 m
GROUP BY ROLLUP(pickup_borough, tip_category)
order by 1, 2