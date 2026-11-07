"""
HYROX Season 8: pacing and station insights.

A mobile first Streamlit page answering README questions Q1 and Q2, plus the Q5
audit note. Data comes from three dbt tables (see data.py):

    q1_station_variance        8 rows   one per station, elite and pro pooled
    q2_station_degradation     5,000    one per race result
    q2_deviation_correlation   7 rows   six divisions plus the pooled ALL row

Run locally:   streamlit run streamlit_app/app.py
"""

import altair as alt
import pandas as pd
import streamlit as st

import data

st.set_page_config(
    page_title="HYROX Season 8 Insights",
    page_icon="🏁",
    layout="centered",          # single column reads best on a phone
    initial_sidebar_state="collapsed",
)

# ---------------------------------------------------------------- constants

STATION_LABELS = {
    "SKIERG_TIME": "SkiErg",
    "SLEDPUSH_TIME": "Sled Push",
    "SLEDPULL_TIME": "Sled Pull",
    "BURPEEBROADJUMP_TIME": "Burpee Broad Jump",
    "ROWERG_TIME": "RowErg",
    "FARMERSCARRY_TIME": "Farmer's Carry",
    "SANDBAGLUNGES_TIME": "Sandbag Lunges",
    "WALLBALLS_TIME": "Wall Balls",
}

DIVISION_ORDER = ["open", "pro", "doubles", "pro_doubles", "elite", "elite_doubles"]
DIVISION_LABELS = {
    "open": "Open",
    "pro": "Pro",
    "doubles": "Doubles",
    "pro_doubles": "Pro Doubles",
    "elite": "Elite",
    "elite_doubles": "Elite Doubles",
    "ALL": "All divisions (pooled)",
}
SMALL_GROUPS = {"elite", "elite_doubles"}  # n = 29 each

# Q2 scatter default view (minutes). All rows stay in the data and the correlation
# table; only the chart's default view is limited to the main range.
Q2_X_DOMAIN = [-12, 4]

ACCENT = "#E4572E"
MUTED = "#8A8F98"

# ---------------------------------------------------------------- styles

st.markdown(
    """
    <style>
      .block-container {padding-top: 1.5rem; padding-bottom: 3rem; max-width: 760px;}
      h1 {font-size: 1.9rem !important; line-height: 1.2;}
      h2 {font-size: 1.35rem !important; margin-top: 1.2rem;}
      .lead {font-size: 1.05rem; color: inherit; opacity: 0.85;}
      .kpi {border-radius: 12px; padding: 0.8rem 1rem; background: rgba(228,87,46,0.08);
            border-left: 4px solid #E4572E; margin: 0.4rem 0 1rem 0;}
      .footnote {font-size: 0.82rem; opacity: 0.75; line-height: 1.45;}
      @media (max-width: 640px) {
        h1 {font-size: 1.55rem !important;}
        .block-container {padding-left: 1rem; padding-right: 1rem;}
      }
    </style>
    """,
    unsafe_allow_html=True,
)


def footnote(lines):
    st.markdown(
        '<div class="footnote">' + "<br>".join(lines) + "</div>",
        unsafe_allow_html=True,
    )


def load_or_stop(loader, what):
    try:
        return loader()
    except data.DataSourceError as exc:
        st.error(f"Couldn't load the {what} right now. Please try again in a few minutes.")
        with st.expander("Technical details"):
            st.code(str(exc))
        st.stop()


# ---------------------------------------------------------------- header

st.title("HYROX Season 8: where races are won and lost")
st.markdown(
    '<p class="lead">Two questions from a sample of 5,000 Season 8 race results: '
    "which stations separate the best athletes, and what happens when you start too fast.</p>",
    unsafe_allow_html=True,
)

# ---------------------------------------------------------------- Q1

st.header("1. Which stations vary most for elite and pro athletes?")

q1 = load_or_stop(data.load_q1, "station data")
q1 = q1.assign(station_label=q1["station"].map(STATION_LABELS).fillna(q1["station"]))
q1 = q1.sort_values("transition_time_variance", ascending=False).reset_index(drop=True)

top = q1.iloc[0]
second = q1.iloc[1]
low = q1.sort_values("transition_time_variance").iloc[:2]
st.markdown(
    f'<div class="kpi"><b>{top.station_label}</b> ({top.transition_time_variance:.2f}) and '
    f'<b>{second.station_label}</b> ({second.transition_time_variance:.2f}) vary most. '
    f'<b>{low.iloc[0].station_label}</b> ({low.iloc[0].transition_time_variance:.2f}) and '
    f'<b>{low.iloc[1].station_label}</b> ({low.iloc[1].transition_time_variance:.2f}) vary least.</div>',
    unsafe_allow_html=True,
)

q1_highlight = set(q1["station_label"].head(2))
q1_chart = (
    alt.Chart(q1)
    .mark_bar(cornerRadiusEnd=4)
    .encode(
        y=alt.Y("station_label:N", sort=list(q1["station_label"]), title=None,
                axis=alt.Axis(labelLimit=140, labelFontSize=12)),
        x=alt.X("transition_time_variance:Q", title="Variance of station time (minutes²)"),
        color=alt.condition(
            alt.FieldOneOfPredicate(field="station_label", oneOf=list(q1_highlight)),
            alt.value(ACCENT),
            alt.value(MUTED),
        ),
        tooltip=[
            alt.Tooltip("station_label:N", title="Station"),
            alt.Tooltip("transition_time_variance:Q", title="Variance", format=".2f"),
            alt.Tooltip("n_obs:Q", title="Results"),
        ],
    )
    .properties(height=320)
)
q1_labels = q1_chart.mark_text(align="left", dx=4, fontSize=11).encode(
    text=alt.Text("transition_time_variance:Q", format=".2f"),
    color=alt.value("#444"),
)
st.altair_chart((q1_chart + q1_labels).configure_view(stroke=None), use_container_width=True)

n_obs = int(q1["n_obs"].max())
footnote([
    f"Sample variance of each station's time, {n_obs} results per station. "
    "Compare stations against each other; variances are not added across stations.",
    "Pooled across four divisions: Pro (252), Pro Doubles (90), Elite (29) and Elite Doubles (29). "
    "Doubles station times are shared between two partners and count once per team.",
    "Station time only. Roxzone (time between stations) is excluded because it is missing "
    "systematically in the elite divisions.",
])

# ---------------------------------------------------------------- Q2

st.header("2. Does a fast first kilometre cost you later?")
st.markdown(
    "**First km deviation** is how much faster (negative) or slower than their own average run "
    "an athlete's first kilometre was. **Degradation** is Wall Balls time minus SkiErg time, "
    "the last station versus the first."
)

q2 = load_or_stop(data.load_q2, "pacing data")
corr = load_or_stop(data.load_q2_correlation, "correlation table")

present = [d for d in DIVISION_ORDER if d in set(q2["division"])]
present += sorted(set(q2["division"]) - set(present))
options = present + ["ALL"]
choice = st.selectbox(
    "Division",
    options,
    index=0,
    format_func=lambda d: DIVISION_LABELS.get(d, d),
    help="Divisions behave very differently, so each is shown on its own. "
         "Choose 'All divisions (pooled)' to see everything together.",
)

view = q2 if choice == "ALL" else q2[q2["division"] == choice]
row = corr[corr["division"] == choice]

if not row.empty:
    r = row.iloc[0]
    st.markdown(
        f'<div class="kpi"><b>{DIVISION_LABELS.get(choice, choice)}</b>: n = {r.n:,}, '
        f"average first km deviation {r.avg_deviation:.2f} min, average degradation "
        f"{r.avg_degradation:.2f} min, correlation {r.corr_dev_vs_degradation:+.2f}.</div>",
        unsafe_allow_html=True,
    )

if choice in SMALL_GROUPS:
    st.warning("Only 29 results in this division, so the pattern here is not reliable.")
if choice == "ALL":
    st.info("Pooled view: all divisions combined. Singles and doubles behave very differently, "
            "so the division views tell the clearer story.")

lo, hi = Q2_X_DOMAIN
outside = int(((view["first_km_deviation"] < lo) | (view["first_km_deviation"] > hi)).sum())
in_range = view[(view["first_km_deviation"] >= lo) & (view["first_km_deviation"] <= hi)]

scatter = (
    alt.Chart(in_range)
    .mark_circle(size=22, opacity=0.35, color=ACCENT)
    .encode(
        x=alt.X("first_km_deviation:Q", title="First km deviation (min, negative = faster start)",
                scale=alt.Scale(domain=Q2_X_DOMAIN, nice=False)),
        y=alt.Y("station_degradation:Q", title="Degradation: Wall Balls minus SkiErg (min)"),
        tooltip=[
            alt.Tooltip("division:N", title="Division"),
            alt.Tooltip("first_km_deviation:Q", title="First km deviation", format=".2f"),
            alt.Tooltip("station_degradation:Q", title="Degradation", format=".2f"),
        ],
    )
)
zero_x = alt.Chart(pd.DataFrame({"x": [0]})).mark_rule(color="#999", strokeDash=[4, 4]).encode(x="x:Q")
zero_y = alt.Chart(pd.DataFrame({"y": [0]})).mark_rule(color="#999", strokeDash=[4, 4]).encode(y="y:Q")
st.altair_chart(
    (scatter + zero_x + zero_y).properties(height=380).configure_view(stroke=None),
    use_container_width=True,
)

q2_notes = []
if outside:
    q2_notes.append(f"{outside} point{'s' if outside != 1 else ''} fall"
                    f"{'' if outside != 1 else 's'} outside the chart range.")
q2_notes += [
    "Results with a missing run or station time are excluded, never counted as zero.",
    "Doubles results count once per team, not once per athlete.",
    "This shows association, not causation.",
]
footnote(q2_notes)

st.subheader("By division")
table = corr.copy()
table["order"] = table["division"].map({d: i for i, d in enumerate(DIVISION_ORDER + ["ALL"])}).fillna(98)
table = table.sort_values("order").drop(columns="order")
table["division"] = table["division"].map(lambda d: "All (pooled)" if d == "ALL" else DIVISION_LABELS.get(d, d))
table = table.rename(columns={
    "division": "Division",
    "n": "n",
    "avg_deviation": "Avg 1st km dev (min)",
    "avg_degradation": "Avg degr. (min)",
    "corr_dev_vs_degradation": "Corr.",
})
st.dataframe(
    table,
    hide_index=True,
    use_container_width=True,
    column_config={
        "n": st.column_config.NumberColumn(format="%d"),
        "Avg 1st km dev (min)": st.column_config.NumberColumn(format="%.2f", help="Average first km deviation"),
        "Avg degr. (min)": st.column_config.NumberColumn(format="%.2f", help="Average degradation: Wall Balls minus SkiErg"),
        "Corr.": st.column_config.NumberColumn(format="%+.2f", help="Correlation between first km deviation and degradation"),
    },
)
footnote([
    "Correlations are computed in the dbt model and shown as is. All rows are included, "
    "including the points outside the chart range.",
    "Elite and Elite Doubles have only 29 results each (about ±0.35 uncertainty on the correlation), "
    "so don't draw conclusions from them.",
])

# ---------------------------------------------------------------- Q5 data notes

st.header("About this data")
with st.expander("Registration audit (Q5)", expanded=False):
    st.markdown(
        "- The registration audit closed on 30 October 2026.\n"
        "- Result IDs are unique across all 5,000 rows, and source result IDs are unique wherever they exist.\n"
        "- Two athletes appeared twice in the same event and division. Both pairs were checked and are "
        "different performances (81.00 vs 115.95 minutes, and 77.88 vs 94.08), not duplicates.\n"
        "- **Caveat:** athlete IDs are built from name, gender, nationality and age group, so two different "
        "athletes with the same details can share an ID. This page does not claim the data is duplicate free "
        "or that prize money integrity is fully proven."
    )
with st.expander("About the sample", expanded=False):
    st.markdown(
        "- 5,000 Season 8 race results.\n"
        "- Times are in minutes.\n"
        "- Missing times mean not recorded. They are excluded, never treated as zero.\n"
        "- Doubles and relay results count once per team."
    )

footnote([f"Data source: {data.data_source_label()}. Refreshed at most once an hour."])
