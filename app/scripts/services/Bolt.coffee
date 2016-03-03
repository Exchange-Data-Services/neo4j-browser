###!
Copyright (c) 2002-2016 "Neo Technology,"
Network Engine for Objects in Lund AB [http://neotechnology.com]

This file is part of Neo4j.

Neo4j is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
###

'use strict';

angular.module('neo4jApp.services')
  .factory 'Bolt', [
    'Settings'
    (Settings) ->
      bolt = window.neo4j.v1
      driver = bolt.driver("bolt://localhost:7687")

      boltResultToRESTResult = (result) ->
        res = result.records
        obj = {
          config: {},
          headers: -> [],
          data: {
            results: [{
              columns: [], 
              data: [],
              stats: {},
              }],
            errors: []
          }
        }
        if result.fields
          obj.data.errors = result.fields
          return obj
        keys = if res.length then Object.keys(res[0]) else []
        obj.data.results[0].columns = keys
        obj.data.results[0].plan = boltPlanToRESTPlan result.summary.plan if result.summary.plan
        obj.data.results[0].plan = boltPlanToRESTPlan result.summary.profile if result.summary.profile
        obj.data.results[0].stats = boltStatsToRESTStats result.summary
        res = itemIntToString res
        rows = res.map((record) ->
          return {
            row: getRESTRowsFromBolt record, keys
            graph: getRESTGraphFromBolt record, keys
          }
        )
        obj.data.results[0]['data'] = rows
        return obj

      getRESTRowsFromBolt = (record, keys) ->
        keys.reduce(((tot, curr) -> tot.concat(extractDataForRowsFormat(record[curr]))), [])

      getRESTGraphFromBolt = (record, keys) ->
        items = keys.map((key) -> record[key])
        graphItems = items.filter((item) -> item instanceof bolt.types.Node || item instanceof bolt.types.Relationship)
        paths = items.filter((item) -> item instanceof bolt.types.Path)
        extractedPaths = extractPathsForGraphFormat paths
        graphItems = graphItems.concat extractedPaths
        graphItems.map((item) -> 
          item.id = item.identity
          delete item.identity
          return item
        )
        nodes = graphItems.filter((item) -> item instanceof bolt.types.Node)
        rels = graphItems.filter((item) -> item instanceof bolt.types.Relationship)
          .map((item) ->
            item.startNode = item.start
            item.endNode = item.end 
            delete item.start
            delete item.end
            return item
          )
        {nodes: nodes, relationships: rels}

      extractDataForRowsFormat = (item) ->
        return item.properties if item instanceof bolt.types.Node
        return item.properties if item instanceof bolt.types.Relationship
        return extractPathForRowsFormat item if item instanceof bolt.types.Path
        item

      extractPathForRowsFormat = (path) ->
        path.segments.map((segment) -> [
          extractDataForRowsFormat(segment.start), 
          extractDataForRowsFormat(segment.relationship),
          extractDataForRowsFormat(segment.end)
        ])

      extractPathsForGraphFormat = (paths) ->
        paths.reduce((all, path) ->
          path.segments.forEach((segment) ->
            all.push(segment.start)
            all.push(segment.end)
            all.push(segment.relationship)
          )
          return all
        , [])

      itemIntToString = (item) ->
        return arrayIntToString item if Array.isArray(item)
        return item if typeof item in ['number', 'string']
        return item if item is null
        return item.toString() if bolt.isInt item
        return objIntToString item if typeof item is 'object'

      arrayIntToString = (arr) ->
       arr.map((item) -> itemIntToString item)

      objIntToString = (obj) ->
        Object.keys(obj).forEach((key) ->
          obj[key] = itemIntToString obj[key]
        )
        obj

      boltPlanToRESTPlan = (plan) ->
        obj = boltPlanToRESTPlanShared plan
        obj['runtime-impl'] = "INTERPRETED"
        obj['planner-impl'] = "IDP"
        obj['version'] = "CYPHER 3.0"
        obj['KeyNames'] = "p"
        obj['planner'] = "COST"
        obj['runtime'] = "INTERPRETED"
        {root: obj}

      boltPlanToRESTPlanShared = (plan) ->
        return {
          operatorType: plan.operatorType,
          LegacyExpression: plan.arguments.LegacyExpression,
          ExpandExpression: plan.arguments.ExpandExpression,
          DbHits: plan.dbHits,
          Rows: plan.rows,
          EstimatedRows: plan.arguments.EstimatedRows,
          identifiers: plan.identifiers,
          children: plan.children.map boltPlanToRESTPlanShared
        }

      boltStatsToRESTStats = (summary) ->
        stats = summary.updateStatistics._stats
        newStats = {}
        Object.keys(stats).forEach((key) ->
          newKey = key.replace(/([A-Z]+)/, (m) -> '_' + m.toLowerCase())
          newStats[newKey] = stats[key]
        )
        newStats['contains_updates'] = summary.updateStatistics.containsUpdates()
        newStats

      return {
        beginTransaction: (opts) -> 
          statement = opts[0]?.statement || ''
          tx = driver.session().beginTransaction()
          return {tx: tx, promise: null} unless statement
          return {tx: tx, promise: tx.run(statement)}
        transaction: (opts, tx) -> 
          tx = tx || driver.session().beginTransaction()
          statement = opts[0]?.statement || ''
          p = tx.run(opts[0].statement)
          tx.commit()
          {tx: tx, promise: p}
        constructResult: (res) ->
          boltResultToRESTResult res
      }
  ]
