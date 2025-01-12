package main

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/mattn/go-sqlite3" // SQLite driver
)

type Score struct {
	Id       int    `json:"id"`
	Score    int    `json:"score"`
	Username string `json:"username"`
}

func initDB() *sql.DB {
	db := conn()

	if !tableExist(db) {
		createTable(db)
	}

	getScores(db)
	return db
}

func getScores(db *sql.DB) []Score {
	N := 10
	sql := fmt.Sprintf("SELECT id, score, username FROM scores ORDER BY score DESC LIMIT %d", N)
	rows, err := db.Query(sql)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	res := make([]Score, 0)

	for rows.Next() {
		var id, score int
		var username string

		// Maybe there is a better way to do this idk
		rows.Scan(&id, &score, &username)
		res = append(res, Score{
			Id:       id,
			Score:    score,
			Username: username,
		})
	}

	return res
}

func conn() *sql.DB {
	dbPath := "scores.db"

	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		log.Fatal(err.Error())
	}

	err = db.Ping()
	if err != nil {
		log.Fatal(err.Error())
	}

	return db
}

func tableExist(db *sql.DB) bool {
	sql := `
		SELECT
			COUNT(*)
		FROM
			sqlite_master
		WHERE
			type='table' AND name='scores';
	`

	var exists bool
	err := db.QueryRow(sql).Scan(&exists)
	if err != nil {
		log.Fatal(err)
	}

	return exists
}

func createTable(db *sql.DB) {
	sql := `
		CREATE TABLE scores (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			score INTEGER NOT NULL,
			username TEXT NOT NULL
		);
	`
	_, err := db.Exec(sql)
	if err != nil {
		log.Fatal(err)
	}
}

func insertScore(score Score, db *sql.DB) {
	if len(score.Username) == 0 {
		return
	}

	if score.Score <= 0 {
		return
	}

	sql := `
		INSERT INTO scores (score, username) VALUES (?, ?)
	`
	_, err := db.Exec(sql, score.Score, score.Username)
	if err != nil {
		log.Fatal(err)
	}
}
