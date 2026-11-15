// Query throughput: WORKERS connections each run QUERIES sequential point lookups with one
// prepared statement. Matches ms/src/main.ms.
use tokio_postgres::{Config, NoTls};

fn env(name: &str, fallback: &str) -> String {
    std::env::var(name).ok().filter(|v| !v.is_empty()).unwrap_or_else(|| fallback.to_string())
}

async fn worker(config: Config, id: i64, queries: i64) -> Result<i64, tokio_postgres::Error> {
    let (client, connection) = config.connect(NoTls).await?;
    tokio::spawn(connection);
    let statement = client.prepare("select id, name, score from items where id = $1").await?;
    let mut sum = 0;
    for i in 0..queries {
        let key = (i * 7919 + id * 104729) % 10000 + 1;
        let row = client.query_one(&statement, &[&key]).await?;
        let _id: i64 = row.get(0);
        let _name: String = row.get(1);
        let score: i64 = row.get(2);
        sum += score;
    }
    Ok(sum)
}

#[tokio::main]
async fn main() {
    let workers: i64 = env("WORKERS", "4").parse().unwrap();
    let queries: i64 = env("QUERIES", "20000").parse().unwrap();
    let mut config = Config::new();
    config
        .host(&env("PGHOST", "127.0.0.1"))
        .port(env("PGPORT", "5432").parse().unwrap())
        .user(&env("PGUSER", "postgres"))
        .password(env("PGPASSWORD", ""))
        .dbname("postgres");
    let tasks: Vec<_> = (0..workers).map(|id| tokio::spawn(worker(config.clone(), id, queries))).collect();
    let mut total = 0;
    for task in tasks {
        total += task.await.unwrap().unwrap();
    }
    println!("checksum {total}");
}
