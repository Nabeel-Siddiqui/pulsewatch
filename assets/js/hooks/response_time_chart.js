// Renders the monitor detail page's 24h response-time line chart, and
// appends a live point whenever the server pushes a "new-chart-point"
// event (a check the PubSub subscription just delivered).
const ResponseTimeChart = {
  mounted() {
    const points = JSON.parse(this.el.dataset.points || "[]")

    this.chart = new Chart(this.el, {
      type: "line",
      data: {
        datasets: [
          {
            label: "Response time (ms)",
            data: points,
            borderColor: "#4f46e5",
            backgroundColor: "rgba(79, 70, 229, 0.1)",
            tension: 0.2,
            pointRadius: 2,
            fill: true
          }
        ]
      },
      options: {
        responsive: true,
        scales: {
          // A plain category axis with pre-formatted "HH:MM" labels from
          // the server — Chart.js's `time` scale needs a separate date
          // adapter package this app doesn't pull in, and a category axis
          // is all a 24h response-time chart actually needs.
          x: { title: { display: true, text: "Time (UTC)" } },
          y: { beginAtZero: true, title: { display: true, text: "ms" } }
        },
        plugins: { legend: { display: false } }
      }
    })

    this.handleEvent("new-chart-point", ({ x, y }) => {
      if (!this.chart) return
      this.chart.data.datasets[0].data.push({ x, y })
      this.chart.update()
    })
  },

  destroyed() {
    if (this.chart) this.chart.destroy()
  }
}

export default ResponseTimeChart
