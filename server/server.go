package main

import (
	"compress/gzip"
	"database/sql"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

func main() {
	db := initDB()
	defer db.Close()

	gameDir := "./public"

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		serveCompressedFile(w, r, gameDir)
	})

	http.HandleFunc("/api/leaderboard", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			getLeaderBoard(w, r, db)
			return
		}
		if r.Method == http.MethodPost {
			postToLeaderBoard(w, r, db)
			return
		}
	})

	port := "8080"
	log.Printf("serving game at http://localhost:%s\n", port)
	err := http.ListenAndServe(":"+port, nil)
	if err != nil {
		log.Printf("Error starting server: %s\n", err)
	}
}

func serveCompressedFile(w http.ResponseWriter, r *http.Request, dir string) {
	w.Header().Set("Cross-Origin-Opener-Policy", "same-origin")
	w.Header().Set("Cross-Origin-Embedder-Policy", "require-corp")

	log.Println(r.URL.Path)

	if r.URL.Path == "/" {
		r.URL.Path = "/index.html"
	}

	filePath := dir + r.URL.Path
	file, err := os.Open(filePath)
	if err != nil {
		log.Println(err)
		http.NotFound(w, r)
		return
	}
	defer file.Close()

	acceptEncoding := r.Header.Get("Accept-Encoding")
	if strings.Contains(acceptEncoding, "gzip") {
		w.Header().Set("Content-Encoding", "gzip")
		compressedWriter := gzip.NewWriter(w)
		defer compressedWriter.Close()

		_, err := io.Copy(compressedWriter, file)
		if err != nil {
			log.Println(err)
			http.Error(w, "Failed to compress file", http.StatusInternalServerError)
		}
	} else {
		w.Header().Set("Content-Type", "application/octet-stream")
		_, err := io.Copy(w, file)
		if err != nil {
			log.Fatal(err)
			http.Error(w, "Failed to serve file", http.StatusInternalServerError)
		}
	}
}

func getLeaderBoard(w http.ResponseWriter, _ *http.Request, db *sql.DB) {
	board := getScores(db)
	log.Printf("GET leaderboard %v\n", board)

	w.Header().Set("Content-Type", "application/json")

	err := json.NewEncoder(w).Encode(board)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
}

func postToLeaderBoard(w http.ResponseWriter, r *http.Request, db *sql.DB) {
	body, err := io.ReadAll(io.Reader(r.Body))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer r.Body.Close()

	var data Score
	err = json.Unmarshal(body, &data)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	log.Printf("POST leaderboard %v\n", data)

	insertScore(data, db)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}
