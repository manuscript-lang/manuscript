---
title: "manuscript programming language"
linkTitle: "manuscript"
---

{{< blocks/cover image_anchor="top" color="primary" >}}
<div class="col-12">
  <div class="hero-content">
    <h1 class="display-1 hero-title">manuscript</h1>
    <p class="lead hero-subtitle">a programming language</p>
    <div class="hero-buttons mt-5">
      <a class="btn btn-primary btn-lg me-3 gradient-btn" href="/docs/">
        <i class="fas fa-rocket me-2"></i>Get Started
      </a>
      <a class="btn btn-outline-light btn-lg github-btn" href="https://github.com/manuscript-lang/manuscript">
        <i class="fab fa-github me-2"></i>GitHub
      </a>
    </div>
  </div>
</div>
{{< /blocks/cover >}}

{{< blocks/section >}}
<div class="container">
  <div class="row justify-content-center">
    <div class="col-lg-10 col-xl-8">
      <div class="example-section">
        <h2 class="display-4 mb-4 text-center">Simple. Readable. Powerful.</h2>
        <div class="code-example-container">
{{< highlight ms >}}
fn fibonacci(n int) int {
  match {
    n <= 1: n
    default: fibonacci(n-1) + fibonacci(n-2)
  }
}

fn main() {
  for i in 1..10 {
    print("fib($i) = $(fibonacci(i))")
  }
}
{{< /highlight >}}
        </div>
      </div>
    </div>
  </div>
</div>
{{< /blocks/section >}}

{{< blocks/section color="light" >}}
<div class="container">
  <div class="row text-center mb-5">
    <div class="col-12">
      <h2 class="display-4 section-title">Why manuscript?</h2>
    </div>
  </div>
  <div class="row features-grid">
    <div class="col-md-4 mb-4">
      <div class="feature-card h-100">
        <div class="feature-icon-container">
          <div class="feature-icon">📖</div>
        </div>
        <div class="card-body text-center">
          <h3 class="card-title">AI First</h3>
          <p class="card-text">Clear, minimal syntax designed for both humans and AI—code reads like prose, making it easy to generate, understand, and maintain.</p>
        </div>
      </div>
    </div>
    <div class="col-md-4 mb-4">
      <div class="feature-card h-100">
        <div class="feature-icon-container">
          <div class="feature-icon">🛡️</div>
        </div>
        <div class="card-body text-center">
          <h3 class="card-title">Safe</h3>
          <p class="card-text">Strong static typing with compile-time error checking. Catch bugs before they ship.</p>
        </div>
      </div>
    </div>
    <div class="col-md-4 mb-4">
      <div class="feature-card h-100">
        <div class="feature-icon-container">
          <div class="feature-icon">⚡</div>
        </div>
        <div class="card-body text-center">
          <h3 class="card-title">Fast</h3>
          <p class="card-text">Compiles to efficient Go code. Access Go's performance and ecosystem.</p>
        </div>
      </div>
    </div>
  </div>
</div>
{{< /blocks/section >}}

{{< blocks/section color="white" >}}
<div class="container">
  <div class="row justify-content-center">
    <div class="col-lg-10">
      <div class="features-detailed">
        <div class="text-center mb-5">
          <h2 class="display-4 section-title">Modern language features</h2>
          <p class="lead text-muted">Everything you need for productive development</p>
        </div>
        <div class="row">
          <div class="col-lg-6 mb-4">
            <div class="feature-item">
              <div class="feature-header">
                <div class="feature-bullet"></div>
                <h4>Optional returns</h4>
              </div>
              <p>Functions automatically return the last expression. No need for explicit <code>return</code> statements in most cases.</p>
            </div>
            <div class="feature-item">
              <div class="feature-header">
                <div class="feature-bullet"></div>
                <h4>Error handling</h4>
              </div>
              <p>Clear distinction between functions that can fail (<code>fn()!</code>) and those that cannot (<code>fn()</code>).</p>
            </div>
            <div class="feature-item">
              <div class="feature-header">
                <div class="feature-bullet"></div>
                <h4>Pattern matching</h4>
              </div>
              <p>Powerful <code>match</code> expressions for handling complex data structures and control flow.</p>
            </div>
          </div>
          <div class="col-lg-6 mb-4">
            <div class="feature-item">
              <div class="feature-header">
                <div class="feature-bullet"></div>
                <h4>Operator chaining</h4>
              </div>
              <p>Write mathematical expressions naturally: <code>a &lt; b &lt; c</code> instead of <code>(a &lt; b) && (b &lt; c)</code>.</p>
            </div>
            <div class="feature-item">
              <div class="feature-header">
                <div class="feature-bullet"></div>
                <h4>Type inference</h4>
              </div>
              <p>Smart type inference reduces boilerplate while maintaining type safety.</p>
            </div>
            <div class="feature-item">
              <div class="feature-header">
                <div class="feature-bullet"></div>
                <h4>Go ecosystem</h4>
              </div>
              <p>Use any Go library, deploy anywhere Go runs, benefit from Go's mature tooling.</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
{{< /blocks/section >}}

{{< blocks/section color="primary" >}}
<div class="container text-center">
  <div class="row justify-content-center">
    <div class="col-lg-8">
      <div class="cta-content">
        <h2 class="display-4 cta-title text-white">Ready to get started?</h2>
        <p class="lead cta-subtitle text-white-50 mb-5">Join developers who are building better software with manuscript</p>
        <div class="cta-buttons">
          <a class="btn btn-light btn-lg me-3 cta-primary-btn" href="/docs/getting-started/">
            <i class="fas fa-play me-2"></i>Start Tutorial
          </a>
          <a class="btn btn-outline-light btn-lg cta-secondary-btn" href="/docs/">
            <i class="fas fa-book me-2"></i>View Documentation
          </a>
        </div>
      </div>
    </div>
  </div>
</div>
{{< /blocks/section >}} 