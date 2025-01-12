FROM golang:1.23.4-alpine

ENV CGO_ENABLED=1

RUN apk --no-cache add ca-certificates build-base

WORKDIR /app

COPY server/ .
RUN go mod download
RUN go build -o lil_tetris .

EXPOSE 8080

CMD ["./lil_tetris"]
