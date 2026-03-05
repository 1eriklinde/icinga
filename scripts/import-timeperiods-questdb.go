// import-timeperiods-questdb.go
// TODO: Query QuestDB for per-host timeperiods and create them in Icinga2.
//
// Planned behaviour:
//   1. Query QUESTDB_TIMEPERIOD_QUERY from QuestDB REST API
//   2. For each host, create or update a TimePeriod object via Icinga2 API
//      (PUT /v1/objects/timeperiods/<name>)
//   3. Assign the timeperiod to the host's check_period and notification_period
//      (POST /v1/objects/hosts/<host_name> with attrs.check_period)
//
// Config is read from config.env (ICINGA2_*, QUESTDB_*)
//
// Run: go run import-timeperiods-questdb.go
//      or build: go build -o import-timeperiods import-timeperiods-questdb.go

package main

func main() {
	// TODO: implement
}
