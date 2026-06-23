//+------------------------------------------------------------------+
//| ImpulsePullbackDetector - OPTIMIZED VERSION                       |
//| Performance: Eliminated redundant array resizing in loops          |
//| Memory: Pre-allocated arrays at initialization                    |
//+------------------------------------------------------------------+

#ifndef IMPULSEPULLBACKDETECTORCLASS_MQH
#define IMPULSEPULLBACKDETECTORCLASS_MQH

#include "InsideBarClass.mqh";
#include "Enums.mqh"

class ImpulsePullbackDetectorClass {
private:
    Trend m_trend;
    bool m_is_inside_bar;
    int m_swing_high_index;
    int m_swing_low_index;
    int m_mother_bar_index;
    double m_swing_high_price;
    double m_swing_low_price;
    
    // IMPROVEMENT 1: Pre-allocated state - prevents repeated resizing
    bool m_buffers_initialized;

public:
    InsideBarClass* m_inside_bar_class;
    
    // Public buffers
    double m_high_zigzag_buffer[];
    double m_low_zigzag_buffer[];
    double m_swing_high_buffer[];
    double m_swing_low_buffer[];
    
    // State tracking
    int m_prev_swing_high_index;
    int m_prev_swing_low_index;
    int m_latest_swing_high_index;
    int m_latest_swing_low_index;
    
    double m_prev_swing_high_price;
    double m_prev_swing_low_price;
    double m_latest_swing_high_price;
    double m_latest_swing_low_price;
    
    // Constructor
    ImpulsePullbackDetectorClass() : m_inside_bar_class(NULL), m_buffers_initialized(false) {}
    
    //+------------------------------------------------------------------+
    //| IMPROVEMENT 2: Initialize once, not every update
    //+------------------------------------------------------------------+
    void Init(InsideBarClass* inside_bar_instance) {
        m_inside_bar_class = inside_bar_instance;
        
        m_trend = TREND_NONE;
        m_is_inside_bar = false;
        m_swing_high_index = -1;
        m_swing_low_index = -1;
        m_swing_high_price = -1;
        m_swing_low_price = -1;
        
        m_prev_swing_high_index = -1;
        m_prev_swing_low_index = -1;
        m_latest_swing_high_index = -1;
        m_latest_swing_low_index = -1;
        
        m_prev_swing_high_price = -1;
        m_prev_swing_low_price = -1;
        m_latest_swing_high_price = -1;
        m_latest_swing_low_price = -1;
        
        // IMPROVEMENT: Initialize arrays, don't resize in loop
        ArrayInitialize(m_high_zigzag_buffer, EMPTY_VALUE);
        ArrayInitialize(m_low_zigzag_buffer, EMPTY_VALUE);
        ArrayInitialize(m_swing_high_buffer, EMPTY_VALUE);
        ArrayInitialize(m_swing_low_buffer, EMPTY_VALUE);
        
        m_buffers_initialized = true;
    }
    
    //+------------------------------------------------------------------+
    //| IMPROVEMENT 3: Pre-allocate buffers once
    //| Call this from parent indicator in OnInit
    //+------------------------------------------------------------------+
    void PreallocateBuffers(int max_bars) {
        if (max_bars <= 0) return;
        
        ArrayResize(m_high_zigzag_buffer, max_bars);
        ArrayResize(m_low_zigzag_buffer, max_bars);
        ArrayResize(m_swing_high_buffer, max_bars);
        ArrayResize(m_swing_low_buffer, max_bars);
        
        ArrayInitialize(m_high_zigzag_buffer, EMPTY_VALUE);
        ArrayInitialize(m_low_zigzag_buffer, EMPTY_VALUE);
        ArrayInitialize(m_swing_high_buffer, EMPTY_VALUE);
        ArrayInitialize(m_swing_low_buffer, EMPTY_VALUE);
    }
    
    //+------------------------------------------------------------------+
    //| OPTIMIZED: Calculate without array resizing in loop
    //+------------------------------------------------------------------+
    void Calculate(int i, const int rates_total, const double &high[], const double &low[]) {
        // IMPROVEMENT 2A: REMOVED ArrayResize() calls from here!
        // These now happen once in OnInit, not every bar
        
        // Skip first few bars (need history for comparison)
        if (i <= 1) {
            return;
        }
        
        // Get current and previous candle data
        double curr_high = high[i];
        double curr_low = low[i];
        int prev_index = i - 1;
        double prev_high = high[i - 1];
        double prev_low = low[i - 1];
        
        // Initialize trend if not set
        if (m_trend == TREND_NONE) {
            if (curr_high > prev_high && curr_low >= prev_low) {
                m_trend = TREND_BULLISH;
                return;
            }
            
            if (curr_low < prev_low && curr_high <= prev_high) {
                m_trend = TREND_BEARISH;
                return;
            }
        }
        
        // Handle inside bar detection
        if (m_is_inside_bar) {
            prev_index = m_mother_bar_index;
        } else {
            if (m_inside_bar_class.GetMotherBarIndex() != -1) {
                m_is_inside_bar = true;
                m_mother_bar_index = m_inside_bar_class.GetMotherBarIndex();
                prev_index = m_mother_bar_index;
            }
        }
        
        // Perform the actual impulse/pullback check
        CheckImpulsePullback(i, prev_index, high, low);
    }
    
    //+------------------------------------------------------------------+
    //| Main Logic: Impulse and Pullback Detection
    //+------------------------------------------------------------------+
    private:
    
    void CheckImpulsePullback(int curr_index, int prev_index, 
                              const double &high[], const double &low[]) {
        double curr_high = high[curr_index];
        double curr_low = low[curr_index];
        double prev_high = high[prev_index];
        double prev_low = low[prev_index];
        
        switch (m_trend) {
            case TREND_BULLISH:
                HandleBullishTrend(curr_high, curr_low, prev_high, prev_low, curr_index, prev_index);
                break;
                
            case TREND_BEARISH:
                HandleBearishTrend(curr_high, curr_low, prev_high, prev_low, curr_index, prev_index);
                break;
        }
    }
    
    void HandleBullishTrend(double curr_high, double curr_low, double prev_high, 
                           double prev_low, int curr_index, int prev_index) {
        // Case 1: Pure impulse - both higher
        if (curr_high > prev_high && curr_low >= prev_low) {
            m_is_inside_bar = false;
            return;
        }
        
        // Case 2: Pure pullback - both lower (trend reversal)
        if (curr_high <= prev_high && curr_low < prev_low) {
            m_trend = TREND_BEARISH;
            m_swing_high_index = prev_index;
            m_swing_high_price = prev_high;
            m_is_inside_bar = false;
            
            AddHighZigZag();
            AddSwingHighPoint();
            return;
        }
        
        // Case 3: Mixed - high impulse but low pullback
        if (curr_high > prev_high && curr_low < prev_low) {
            m_swing_high_index = prev_index;
            m_swing_high_price = prev_high;
            m_swing_low_index = curr_index;
            m_swing_low_price = curr_low;
            m_is_inside_bar = false;
            
            AddHighZigZag();
            AddLowZigZag();
            AddSwingHighPoint();
            AddSwingLowPoint();
            return;
        }
    }
    
    void HandleBearishTrend(double curr_high, double curr_low, double prev_high, 
                           double prev_low, int curr_index, int prev_index) {
        // Case 1: Pure impulse - both lower
        if (curr_low < prev_low && curr_high <= prev_high) {
            m_is_inside_bar = false;
            return;
        }
        
        // Case 2: Pure pullback - both higher (trend reversal)
        if (curr_high > prev_high && curr_low >= prev_low) {
            m_trend = TREND_BULLISH;
            m_swing_low_index = prev_index;
            m_swing_low_price = prev_low;
            m_is_inside_bar = false;
            
            AddLowZigZag();
            AddSwingLowPoint();
            return;
        }
        
        // Case 3: Mixed - low impulse but high pullback
        if (curr_high > prev_high && curr_low < prev_low) {
            m_swing_high_index = curr_index;
            m_swing_high_price = curr_high;
            m_swing_low_index = prev_index;
            m_swing_low_price = prev_low;
            m_is_inside_bar = false;
            
            AddHighZigZag();
            AddLowZigZag();
            AddSwingHighPoint();
            AddSwingLowPoint();
            return;
        }
    }
    
    void AddHighZigZag() {
        if (m_swing_high_index >= 0 && m_swing_high_index < ArraySize(m_high_zigzag_buffer)) {
            m_high_zigzag_buffer[m_swing_high_index] = m_swing_high_price;
        }
    }
    
    void AddLowZigZag() {
        if (m_swing_low_index >= 0 && m_swing_low_index < ArraySize(m_low_zigzag_buffer)) {
            m_low_zigzag_buffer[m_swing_low_index] = m_swing_low_price;
        }
    }
    
    void AddSwingHighPoint() {
        if (m_swing_high_index >= 0 && m_swing_high_index < ArraySize(m_swing_high_buffer)) {
            m_swing_high_buffer[m_swing_high_index] = m_swing_high_price;
            
            m_prev_swing_high_index = m_latest_swing_high_index;
            m_prev_swing_high_price = m_latest_swing_high_price;
            
            m_latest_swing_high_index = m_swing_high_index;
            m_latest_swing_high_price = m_swing_high_price;
        }
    }
    
    void AddSwingLowPoint() {
        if (m_swing_low_index >= 0 && m_swing_low_index < ArraySize(m_swing_low_buffer)) {
            m_swing_low_buffer[m_swing_low_index] = m_swing_low_price;
            
            m_prev_swing_low_index = m_latest_swing_low_index;
            m_prev_swing_low_price = m_latest_swing_low_price;
            
            m_latest_swing_low_index = m_swing_low_index;
            m_latest_swing_low_price = m_swing_low_price;
        }
    }
    
    public:
    
    //+------------------------------------------------------------------+
    //| Getter Methods - Access state safely
    //+------------------------------------------------------------------+
    int GetLatestSwingHighIndex() const {
        return m_latest_swing_high_index;
    }
    
    int GetLatestSwingLowIndex() const {
        return m_latest_swing_low_index;
    }
    
    int GetPrevSwingHighIndex() const {
        return m_prev_swing_high_index;
    }
    
    int GetPrevSwingLowIndex() const {
        return m_prev_swing_low_index;
    }
    
    double GetLatestSwingHighPrice() const {
        return m_latest_swing_high_price;
    }
    
    double GetLatestSwingLowPrice() const {
        return m_latest_swing_low_price;
    }
    
    Trend GetTrend() const {
        return m_trend;
    }
};

#endif // IMPULSEPULLBACKDETECTORCLASS_MQH
